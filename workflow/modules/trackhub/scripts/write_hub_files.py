from os.path import basename

# https://genome.ucsc.edu/goldenPath/help/hgTracksHelp.html#UseOneFile
hub_text = """hub {genome}
shortLabel {genome} snpArcher Track Hub
longLabel {genome} snpArcher Track Hub
useOneFile on
email {email}\n"""

vcf_track_txt = """track VCF
bigDataUrl {vcf_file}
shortLabel VCF
longLabel VCF
visibility squish
type vcfTabix\n"""

window_parent_txt = """track {track_type}
compositeTrack on
shortLabel {track_type}
longLabel {track_type}
color 200,100,0
altColor 0,102,204
autoScale on
type bigWig
allButtonPair on
visibility full\n"""

window_track_txt = """track {track_name}
parent {parent} on
bigDataUrl {data_url}
type bigWig
shortLabel {label}
longLabel {label}\n"""

allele_freq_txt = """track MinorAlleleFrequency
bigDataUrl {data_url}
type bigWig
color 200,100,0
altColor 0,102,204
autoScale on
visibility full
shortLabel Minor Allele Frequency
longLabel Minor Allele Frequency\n"""

snp_depth_txt = """track SNPDepth
bigDataUrl {data_url}
type bigWig
color 200,100,0
altColor 0,102,204
autoScale on
visibility full
shortLabel SNP Depth
longLabel SNP Depth\n"""

coverage_track_txt = """track NonCallableSites
bigDataUrl {cov_file}
shortLabel Non Callable Sites
type bigBed
longLabel Non Callable Sites
color 0,0,255
visibility dense\n"""


def human_format(num):
    num = float("{:.3g}".format(num))
    magnitude = 0
    while abs(num) >= 1000:
        magnitude += 1
        num /= 1000.0
    return "{}{}".format(
        "{:f}".format(num).rstrip("0").rstrip("."), ["", "K", "M", "B", "T"][magnitude]
    )


def main():
    file_types = snakemake.params["file_types"]  # noqa: F821
    email = snakemake.params["email"]  # noqa: F821
    trackhub_windows = snakemake.params["windows"]  # noqa: F821
    vcf_file = basename(snakemake.input["vcf"][0])  # noqa: F821
    cov_file = basename(snakemake.input["callable_sites"][0])  # noqa: F821
    freq_file = basename(snakemake.input["allele_freq"][0]) # noqa: F821
    depth_file = basename(snakemake.input["depth"][0])  # noqa: F821
    genome = snakemake.params["refGenome"]  # noqa: F821
    trackhub_file = snakemake.output["trackhub_file"]  # noqa: F821

    with open(trackhub_file, "w") as out:
        print(hub_text.format(genome=genome, email=email), file=out)
        print(f"genome {genome}\n", file=out)
        print(vcf_track_txt.format(vcf_file=vcf_file), file=out)
        print(coverage_track_txt.format(cov_file=cov_file), file=out)
        print(allele_freq_txt.format(data_url=freq_file), file=out)
        print(snp_depth_txt.format(data_url=depth_file), file=out)

        for file in file_types:
            print(window_parent_txt.format(track_type=file), file=out)
            for window in trackhub_windows:
                track_name = f"{file}_{human_format(window)}_bp_bins"
                label = f"{file} {human_format(window)} bp bins"
                url = f"{file}_{window}.bw"
                print(
                    window_track_txt.format(track_name=track_name, label=label, parent=file, data_url=url),
                    file=out,
                )

if __name__ == "__main__":
    main()
