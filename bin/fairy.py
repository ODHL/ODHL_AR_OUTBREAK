#!/usr/bin/env python3

import pandas as pd
import argparse
import os
from datetime import date

# Function to get the script version
def get_version():
    return "2.0.0"

def parse_args():
    """Parse command-line arguments for the script."""
    parser = argparse.ArgumentParser(
        description="Compare raw and trimmed read statistics to check for matching read pairs and summarize QC results."
    )
    parser.add_argument('-r', '--raw_read', dest="raw_read", required=True,
                        help="Path to the raw reads statistics file.")
    parser.add_argument('-f', '--summary_file', dest="summary_file", required=True,
                        help="Path to the summary file.")
    parser.add_argument('-t', '--trimd_read', dest="trimd_read", default=None,
                        help="Path to the trimmed reads statistics file (optional).")
    parser.add_argument('-b', '--busco', dest="busco", action='store_true', default=False,
                        help='Use this flag for CDC pipelines to include BUSCO checks.')
    parser.add_argument('--version', action='version', version=get_version(),
                        help="Show the version of the script.")
    
    return parser.parse_args()

def reads_compare(raw_read_file, trimd_file, summary_file, busco):
    """Compare read statistics and generate summary."""
    prefix = os.path.splitext(raw_read_file)[0]  # Get the base name for output files
    aggr_read_stats = pd.read_csv(raw_read_file, sep="\t")

    # Check if there is a trimmed file
    if trimd_file:
        aggr_trimd_stats = pd.read_csv(trimd_file, sep="\t")
        outcome = check_trimmed_reads(aggr_trimd_stats, prefix, busco)
    else:
        outcome = check_raw_reads(aggr_read_stats, prefix, busco)

    # Write the outcome to the summary file
    with open(summary_file, "a") as tmp:
        tmp.write(outcome)

    # Create a new summary file to avoid overwriting
    new_summary_file = f"{prefix}_summary_fastp.txt"
    os.rename(summary_file, new_summary_file)

def check_trimmed_reads(aggr_trimd_stats, prefix, busco):
    """Check trimmed reads statistics and generate summary."""
    approved = f"\nPASSED: There are reads in {prefix} R1/R2 after trimming."
    failure = f"\nFAILED: There are 0 reads in {prefix} R1/R2 after trimming!"
    
    if aggr_trimd_stats["R1[reads]"].values[0] > 0 and aggr_trimd_stats["R2[reads]"].values[0] > 0:
        return approved
    else:
        raw_stats = get_read_stats(aggr_trimd_stats, trimmed=True)
        warning_count = write_synopsis(prefix, busco, *raw_stats)
        write_summary_line(prefix, busco, warning_count, "No reads after trimming!")
        return failure

def check_raw_reads(aggr_read_stats, prefix, busco):
    """Check raw reads statistics and generate summary."""
    approved = f"PASSED: Read pairs for {prefix} are equal."
    failure = "FAILED: The number of reads in R1/R2 are NOT the same!"

    if aggr_read_stats["R1[reads]"].equals(aggr_read_stats["R2[reads]"]):
        return approved
    else:
        raw_stats = get_read_stats(aggr_read_stats, trimmed=False)
        warning_count = write_synopsis(prefix, busco, *raw_stats)
        write_summary_line(prefix, busco, warning_count, "Unequal number of reads in R1/R2!")
        return failure

def get_read_stats(aggr_read_stats, trimmed):
    """Extract statistics from the aggregated read stats."""
    length_R1 = str(aggr_read_stats["R1[bp]"].values[0])
    length_R2 = str(aggr_read_stats["R2[bp]"].values[0])
    reads = int(aggr_read_stats["Total_Sequenced_[reads]"].values[0])
    pairs = str(reads // 2)
    orphaned_reads = str(aggr_read_stats["Unpaired[reads]"].values[0]) if trimmed else str(0)
    Q30_R1_rounded = round((float(aggr_read_stats["Q30_R1_[%]"].values[0]) * 100), 2)
    Q30_R2_rounded = round((float(aggr_read_stats["Q30_R2_[%]"].values[0]) * 100), 2)
    
    return length_R1, length_R2, reads, pairs, Q30_R1_rounded, Q30_R2_rounded, orphaned_reads

def write_synopsis(sample_name, busco, raw_length_R1, raw_length_R2, raw_reads, raw_pairs, raw_Q30_R1_rounded, raw_Q30_R2_rounded, trimd_file, trimd_length_R1, trimd_length_R2, trimd_reads, trimd_pairs, trimd_Q30_R1_rounded, trimd_Q30_R2_rounded, orphaned_reads):
    """Write a synopsis of the QC check results."""
    status = "FAILED"
    warning_count = 0
    Error = "Unequal number of reads in R1/R2!\n" if not trimd_file else "No reads after trimming!\n"

    with open(f"{sample_name}.synopsis", "a") as f:
        today = date.today()
        f.write("---------- Checking " + sample_name + " for successful completion on ----------\n")
        f.write("Summarized                    : SUCCESS : " + str(today) + "\n")
        f.write("FASTQs                        : SUCCESS :  R1: " + raw_length_R1 + "bps R2: " + raw_length_R2 + "bps\n")
        
        # RAW_READ_COUNTS
        if 1 <= raw_reads <= 1000000:
            f.write(f"RAW_READ_COUNTS               : WARNING : Low individual read count before trimming: {raw_reads} ({raw_pairs} paired reads)\n")
            warning_count += 1
        elif raw_reads <= 0:
            f.write(f"RAW_READ_COUNTS               : FAILED  : No individual read count before trimming: {raw_reads} ({raw_pairs} paired reads)\n")
        else:
            f.write(f"RAW_READ_COUNTS               : SUCCESS : {raw_reads} individual reads found in sample ({raw_pairs} paired reads)\n")

        # Q30 checks
        if raw_Q30_R1_rounded < 90:
            f.write(f"RAW_Q30_R1%                   : WARNING : Q30_R1% at {raw_Q30_R1_rounded}% (Threshold is 90%)\n")
            warning_count += 1
        else:
            f.write(f"RAW_Q30_R1%                   : SUCCESS : Q30_R1% at {raw_Q30_R1_rounded}% (Threshold is 90%)\n")

        if raw_Q30_R2_rounded < 70:
            f.write(f"RAW_Q30_R2%                   : WARNING : Q30_R2% at {raw_Q30_R2_rounded}% (Threshold is 70%)\n")
            warning_count += 1
        else:
            f.write(f"RAW_Q30_R2%                   : SUCCESS : Q30_R2% at {raw_Q30_R2_rounded}% (Threshold is 70%)\n")

        # Trimming details
        if trimd_file is None:
            f.write("TRIMMED_READ_COUNTS           : FAILED  : No trimming performed.\n")
            f.write("TRIMMED_Q30_R1%               : FAILED  : No trimming performed.\n")
            f.write("TRIMMED_Q30_R2%               : FAILED  : No trimming performed.\n")
        else:
            f.write("TRIMMED_READ_COUNTS           : FAILED  : No individual read count after trimming!\n")

        # Additional failure reasons
        f.write("---------- " + sample_name + " completed as " + status + " ----------\n")

    return warning_count

def write_summary_line(prefix, busco, warning_count, error):
    """Write summary statistics to a TSV file.""" 
    column_names = ['ID', 'Auto_QC_Outcome', 'Warning_Count', 'Auto_QC_Failure_Reason']
    data = [[prefix, 'FAIL', warning_count, error]]
    df = pd.DataFrame(data, columns=column_names)
    df.to_csv(f"{prefix}_summaryline.tsv", sep="\t", index=False)

def main():
    args = parse_args()
    reads_compare(args.raw_read, args.trimd_read, args.summary_file, args.busco)

if __name__ == '__main__':
    main()
