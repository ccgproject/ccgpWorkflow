localrules: collect_sumstats, download_reference
ruleorder: index_ref > download_reference
### RULES ###

rule get_fastq_pe:
    output:
        temp(config["fastqDir"] + "{Organism}/{sample}/{run}_1.fastq"),
        temp(config["fastqDir"] + "{Organism}/{sample}/{run}_2.fastq")
    params:
        outdir = config["fastqDir"] + "{Organism}/{sample}/",
        tmpdir = config['tmp_dir']
    conda:
        "../envs/fastq2bam.yml"
    threads:
        res_config['get_fastq_pe']['threads']
    log:
        "logs/{Organism}/fasterq_dump/{sample}/{run}.txt"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['get_fastq_pe']['mem']
    shell:
        "fasterq-dump {wildcards.run} -O {params.outdir} -t {params.tmpdir} -e {threads} &> {log}"

rule gzip_fastq:
    input:
        config["fastqDir"] + "{Organism}/{sample}/{run}_1.fastq",
        config["fastqDir"] + "{Organism}/{sample}/{run}_2.fastq"
    output:
        temp(config["fastqDir"] + "{Organism}/{sample}/{run}_1.fastq.gz"),
        temp(config["fastqDir"] + "{Organism}/{sample}/{run}_2.fastq.gz")
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['gzip_fastq']['mem']
    shell:
        "gzip {input}"

rule download_reference:
    output:
        outdir = directory(config["refGenomeDir"] + "{refGenome}"),
        ref = config["refGenomeDir"] + "{refGenome}.fna"
    params:
        dataset = config["refGenomeDir"] + "{refGenome}_dataset.zip"
    log:
        "logs/dl_reference/{refGenome}.log"
    conda:
        "../envs/fastq2bam.yml"
    shell:
        "datasets download genome accession --exclude-gff3 --exclude-protein --exclude-rna --filename {params.dataset} {wildcards.refGenome} &> {log}"
        "&& 7z x {params.dataset} -aoa -o{output.outdir}"
        "&& cat {output.outdir}/ncbi_dataset/data/{wildcards.refGenome}/*.fna > {output.ref}"

rule index_ref:
    input:
        ref = config["refGenomeDir"] + "{refGenome}.fna"
    output:
        indexes = expand(config["refGenomeDir"] + "{{refGenome}}.fna.{ext}", ext=["sa", "pac", "bwt", "ann", "amb"]),
        fai = config["refGenomeDir"] + "{refGenome}.fna" + ".fai",
        dictf = config["refGenomeDir"] + "{refGenome}" + ".dict"
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['index_ref']['mem']
    log:
        "logs/index_ref/{refGenome}.log"
    shell:
        """
        bwa index {input.ref} 2> {log}
        samtools faidx {input.ref} --output {output.fai}
        picard CreateSequenceDictionary REFERENCE={input.ref} OUTPUT={output.dictf} >> {log} 2>&1
        """

rule fastp:
    input:
        unpack(get_reads)
    output:
        r1 = temp(config['output'] + "{Organism}/{refGenome}/" + config['fastqFilterDir'] + "{sample}/{run}_1.fastq.gz"),
        r2 = temp(config['output'] + "{Organism}/{refGenome}/" + config['fastqFilterDir'] + "{sample}/{run}_2.fastq.gz"),
        summ = temp(config['output'] + "{Organism}/{refGenome}/" + config['sumstatDir'] + "{sample}/{run}.out")
    conda:
        "../envs/fastq2bam.yml"
    threads:
        res_config['fastp']['threads']
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['fastp']['mem']
    log:
        "logs/{Organism}/fastp/{refGenome}_{sample}_{run}.txt"
    shell:
        "fastp --in1 {input.r1} --in2 {input.r2} "
        "--out1 {output.r1} --out2 {output.r2} "
        "--thread {threads} "
        "--detect_adapter_for_pe "
        "-j /dev/null -h /dev/null "
        "2> {output.summ} > {log}"

rule bwa_map:
    input:
        ref = config["refGenomeDir"] + "{refGenome}.fna",
        r1 = config['output'] + "{Organism}/{refGenome}/" + config['fastqFilterDir'] + "{sample}/{run}_1.fastq.gz",
        r2 = config['output'] + "{Organism}/{refGenome}/" + config['fastqFilterDir'] + "{sample}/{run}_2.fastq.gz",
        indices = expand(config["refGenomeDir"] + "{{refGenome}}.fna.{ext}", ext=["sa", "pac", "bwt", "ann", "amb"])
    output:
        bam = temp(config['output'] + "{Organism}/{refGenome}/" + config['bamDir'] + "preMerge/{sample}/{run}.bam")
    params:
        get_read_group
    conda:
        "../envs/fastq2bam.yml"
    threads:
        res_config['bwa_map']['threads']
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['bwa_map']['mem']
    log:
        "logs/{Organism}/bwa/{refGenome}_{sample}_{run}.txt"
    benchmark:
        "benchmarks/{Organism}/bwa/{refGenome}_{sample}_{run}.txt"
    shell:
        "bwa mem -M -t {threads} {params} {input.ref} {input.r1} {input.r2} 2> {log} | samtools sort -o {output.bam} -"

rule merge_bams:
    input:
        lambda wildcards:
        expand(config['output'] + "{{Organism}}/{{refGenome}}/" + config['bamDir'] + "preMerge/{{sample}}/{run}.bam", run=samples.loc[samples['BioSample'] == wildcards.sample]['Run'].tolist())
    output:
        bam = temp(config['output'] + "{Organism}/{refGenome}/" + config['bamDir'] + "postMerge/{sample}.bam"),
        bai = temp(config['output'] + "{Organism}/{refGenome}/" + config['bamDir'] + "postMerge/{sample}.bam.bai")
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['merge_bams']['mem']
    shell:
        "samtools merge {output.bam} {input} && samtools index {output.bam}"

rule dedup:
    input:
        bam = config['output'] + "{Organism}/{refGenome}/" + config['bamDir'] + "postMerge/{sample}.bam",
        bai = config['output'] + "{Organism}/{refGenome}/" + config['bamDir'] + "postMerge/{sample}.bam.bai"
    output:
        dedupBam = config['output'] + "{Organism}/{refGenome}/" + config['bamDir'] + "{sample}" + config['bam_suffix'],
        dedupMet = config['output'] + "{Organism}/{refGenome}/" + config['sumstatDir'] + "{sample}_dedupMetrics.txt"
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['dedup']['mem']
    log:
        "logs/{Organism}/dedup/{refGenome}_{sample}.txt"
    benchmark:
        "benchmarks/{Organism}/dedup/{refGenome}_{sample}.txt"
    shell:
        "picard MarkDuplicates -Xmx{resources.mem_mb}M I={input[0]} O={output.dedupBam} METRICS_FILE={output.dedupMet} REMOVE_DUPLICATES=false TAGGING_POLICY=All &> {log}\n"
        "picard BuildBamIndex I={output.dedupBam} &>> {log}"

rule bam_sumstats:
    input:
        bam = config['output'] + "{Organism}/{refGenome}/" + config['bamDir'] + "{sample}" + config['bam_suffix'],
        ref = config["refGenomeDir"] + "{refGenome}.fna"
    output:
        cov = config['output'] + "{Organism}/{refGenome}/" + config['sumstatDir'] + "{sample}_coverage.txt",
        alnSum = config['output'] + "{Organism}/{refGenome}/" + config['sumstatDir'] + "{sample}_AlnSumMets.txt",
        val = config['output'] + "{Organism}/{refGenome}/" + config['sumstatDir'] + "{sample}_validate.txt"
    conda:
        "../envs/fastq2bam.yml"
    resources:
        mem_mb = lambda wildcards, attempt: attempt * res_config['bam_sumstats']['mem']
    shell:
        "samtools coverage --output {output.cov} {input.bam}\n"
        "picard CollectAlignmentSummaryMetrics I={input.bam} R={input.ref} O={output.alnSum}\n"
        # The following ValidateSamFile exits with non-zero status when a BAM file contains errors,
        # causing snakemake to exit and remove these output files.  I cirumvent this by appending "|| true".
        # I also ignore "INVALID_TAG_NM" because it isn't used by GATK but causes errors at this step
        "picard ValidateSamFile I={input.bam} R={input.ref} O={output.val} IGNORE=INVALID_TAG_NM || true"

rule collect_fastp_stats:
    input:
        lambda wildcards:
            expand(config['output'] + "{{Organism}}/{{refGenome}}/" + config['sumstatDir'] + "{{sample}}/{run}.out", run=samples.loc[samples['BioSample'] == wildcards.sample]['Run'].tolist())
    output:
        config['output'] + "{Organism}/{refGenome}/" + config['sumstatDir'] + "{sample}_fastp.out"
    shell:
        "cat {input} > {output}"

rule collect_sumstats:
    input:
        unpack(get_sumstats)
    output:
        config['output'] + "{Organism}/{refGenome}/" + "bam_sumstats.txt"
    run:
        FractionReadsPassFilter, NumFilteredReads = helperFun.collectFastpOutput(input.fastpFiles)
        PercentDuplicates = helperFun.collectDedupMetrics(input.dedupFiles)
        PercentHQreads, PercentHQbases = helperFun.collectAlnSumMets(input.alnSumMetsFiles)
        SeqDepths, CoveredBases = helperFun.collectCoverageMetrics(input.coverageFiles)
        validateSams = helperFun.collectValidationStatus(input.validateFiles)

        helperFun.printBamSumStats(FractionReadsPassFilter, NumFilteredReads, PercentDuplicates, PercentHQreads, PercentHQbases, SeqDepths, CoveredBases, validateSams, config["output"], wildcards)