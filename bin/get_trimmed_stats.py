#!/usr/bin/env python3

import sys
import os
import json
import argparse
from decimal import *
getcontext().prec = 4
from argparse import ArgumentParser
import pandas as pd
from datetime import date


##Makes pre- and post-filtering QC outputs
##Usage: >python3 FastP_QC.py paired_fastp.json single_fastp_json Isolate_Name
##Written by Rich Stanton (njr5@cdc.gov) and Nick Vlachos (nvx4@cdc.gov)

# Function to get the script version
def get_version():
    return "1.0.0"

def parse_args():
    """Parse command-line arguments for the script."""
    parser = argparse.ArgumentParser(
        description="Compare raw and trimmed read statistics to check for matching read pairs and summarize QC results."
    )
    parser.add_argument('-r', '--raw_read', dest="raw_read", required=True,
                        help="Path to the raw reads statistics file.")
    parser.add_argument('-b', '--busco', dest="busco", action='store_true', default=False,
                        help='Use this flag for CDC pipelines to include BUSCO checks.')
    parser.add_argument('--version', action='version', version=get_version(),
                        help="Show the version of the script.")
    parser.add_argument("-t", "--trimmed_json", dest="trimmed_json", action="store", required=True, 
                        help="Json from fastp output on trimmed reads")
    parser.add_argument("-s", "--single_json", dest="single_json", action="store", required=True, 
                     help="Json from fastp output on single reads.")
    parser.add_argument("-n", "--name", dest="name", action="store", required=True, 
                     help="Sample name")
    parser.add_argument('-oTC', '--out_trimd_counts', dest="out_trimd_counts", default=False,
                        help='output file name')    # Argument to show script version
    parser.add_argument('-oS', '--out_summary', dest="out_summary", default=False,
                        help='output file name')    # Argument to show script version
    args = parser.parse_args()
    return args

def FastP_QC_before(input_json, output_file, name):
    """Makes a QC output file from an input FastP json"""
    Out = open(output_file, 'w')
    Out.write('Name\tR1[reads]\tR1[bp]\tR2[reads]\tR2[bp]\tQ20_Total_[bp]\tQ30_Total_[bp]\tQ20_R1_[bp]\tQ20_R2_[bp]\tQ20_R1_[%]\tQ20_R2_[%]\tQ30_R1_[bp]\tQ30_R2_[bp]\tQ30_R1_[%]\tQ30_R2_[%]\tTotal_Sequenced_[bp]\tTotal_Sequenced_[reads]\n')
    f = open(input_json)
    data = json.load(f)
    f.close()
    paired_total_info = data['summary']['before_filtering']
    Q20_Total = str(paired_total_info['q20_bases'])
    Q30_Total = str(paired_total_info['q30_bases'])
    Total_Sequenced_bp = str(paired_total_info['total_bases'])
    Total_Sequenced_reads = str(paired_total_info['total_reads'])
    Info1 = data['read1_before_filtering']
    raw_R1_reads = str(Info1['total_reads'])
    raw_R1_bases = str(Info1['total_bases'])
    Q20_R1_bp = str(Info1['q20_bases'])
    Q20_R1_bp = str(Info1['q20_bases'])
    Q30_R1_bp = str(Info1['q30_bases'])
    Info2 = data
        #check if there are reads otherwise dividing by zero throw
    if Decimal(Info1['total_bases']) == 0:
        Q20_R1_percent, Q20_R2_percent, Q30_R1_percent, Q30_R2_percent = (str(0) for i in range(4))
    else:
        Q20_R1_percent = str(Decimal(Info1['q20_bases']) / Decimal(Info1['total_bases']))
        Q30_R1_percent = str(Decimal(Info1['q30_bases']) / Decimal(Info1['total_bases']))
        Q20_R2_percent = str(Decimal(Info2['q20_bases']) / Decimal(Info2['total_bases']))
        Q30_R2_percent = str(Decimal(Info2['q30_bases']) / Decimal(Info2['total_bases']))
    raw_R2_reads = str(Info2['total_reads'])
    raw_R2_bases = str(Info2['total_bases'])
    Q20_R2_bp = str(Info2['q20_bases'])
    Q30_R2_bp = str(Info2['q30_bases'])
    Line = name + '\t' + raw_R1_reads + '\t' + raw_R1_bases + '\t' + raw_R2_reads + '\t' + raw_R2_bases + '\t' + Q20_Total + '\t' + Q30_Total + '\t' + Q20_R1_bp + '\t' + Q20_R2_bp + '\t' + Q20_R1_percent + '\t' + Q20_R2_percent + '\t' + Q30_R1_bp + '\t' + Q30_R2_bp + '\t' + Q30_R1_percent + '\t' + Q30_R2_percent + '\t' + Total_Sequenced_bp + '\t' + Total_Sequenced_reads
    Out.write(Line)
    Out.close()

def FastP_QC_after(input_trimmed_json, input_singles_json, output_file, name):
    """Makes a QC output file from an input FastP json for orphaned reads"""
    # prepare output
    Out = open(output_file, 'w')
    Out.write('Name\tR1[reads]\tR1[bp]\tR2[reads]\tR2[bp]\tUnpaired[reads]\tUnpaired[bps]\tQ20_Total_[bp]\tQ30_Total_[bp]\tQ20_R1_[bp]\tQ20_R2_[bp]\tQ20_unpaired[bp]\tQ20_R1_[%]\tQ20_R2_[%]\tQ20_unpaired[%]\tQ30_R1_[bp]\tQ30_R2_[bp]\tQ30_unpaired[bp]\tQ30_R1_[%]\tQ30_R2_[%]\tQ30_unpaired[%]\tTotal_Sequenced_[bp]\tPaired_Sequenced_[reads]\tTotal_Sequenced_[reads]\n')
    
    # Perform QC on TRIMMED
    f = open(input_trimmed_json)
    data = json.load(f)
    f.close()
    
    # Summary info for trimmed
    paired_total_info = data['summary']['after_filtering']
    Q20_Total_trimmed = str(paired_total_info['q20_bases'])
    Q30_Total_trimmed = str(paired_total_info['q30_bases'])
    Trimmed_Sequenced_bp = str(paired_total_info['total_bases'])
    Trimmed_Sequenced_reads = str(paired_total_info['total_reads'])

    # read1
    raw_total_info = data['read1_before_filtering']
    raw_R1_reads = str(raw_total_info['total_reads'])
    raw_R1_bases = str(raw_total_info['total_bases'])
    Q20_R1_bp = str(raw_total_info['q20_bases'])
    Q20_R1_percent = str(Decimal(Q20_R1_bp) / Decimal(raw_R1_bases))
    Q30_R1_bp = str(raw_total_info['q30_bases'])
    Q30_R1_percent = str(Decimal(Q30_R1_bp) / Decimal(raw_R1_bases))

    raw_total_info = data['read2_before_filtering']
    raw_R2_reads = str(raw_total_info['total_reads'])
    raw_R2_bases = str(raw_total_info['total_bases'])
    Q20_R2_bp = str(raw_total_info['q20_bases'])
    Q20_R2_percent = str(Decimal(Q20_R2_bp) / Decimal(raw_R2_bases))
    Q30_R2_bp = str(raw_total_info['q30_bases'])
    Q30_R2_percent = str(Decimal(Q30_R2_bp) / Decimal(raw_R2_bases))

    # Perform QC on single
    f = open(input_singles_json)
    data = json.load(f)
    f.close()

    # Summary info for single
    singles_total_info = data['summary']['after_filtering']
    Q20_Total_singles = str(singles_total_info['q20_bases'])
    Q30_Total_singles = str(singles_total_info['q30_bases'])
    Singles_Sequenced_bp = str(singles_total_info['total_bases'])
    Singles_Sequenced_reads = str(singles_total_info['total_reads'])
    unpaired_reads = str(singles_total_info['total_reads'])
    unpaired_bases = str(singles_total_info['total_bases'])
    Q20_unpaired_percent=str(round(singles_total_info['q20_rate'],4))
    Q30_unpaired_percent=str(round(singles_total_info['q30_rate'],4))
    Q20_Total = str(int(Q20_Total_trimmed) + int(Q20_Total_singles))
    Q30_Total = str(int(Q30_Total_trimmed) + int(Q30_Total_singles))

    # summary for both
    Total_Sequenced_bp = str(int(Trimmed_Sequenced_bp) + int(Singles_Sequenced_bp))
    Total_Sequenced_reads = str(int(Trimmed_Sequenced_reads) + int(Singles_Sequenced_reads))

    Out.write('Name\tR1[reads]\tR1[bp]\tR2[reads]\tR2[bp]\tUnpaired[reads]\tUnpaired[bps]\tQ20_Total_[bp]\tQ30_Total_[bp]\tQ20_R1_[bp]\tQ20_R2_[bp]\tQ20_unpaired[bp]\tQ20_R1_[%]\tQ20_R2_[%]\tQ20_unpaired[%]\tQ30_R1_[bp]\tQ30_R2_[bp]\tQ30_unpaired[bp]\tQ30_R1_[%]\tQ30_R2_[%]\tQ30_unpaired[%]\tTotal_Sequenced_[bp]\tPaired_Sequenced_[reads]\tTotal_Sequenced_[reads]\n')

    Line = name + '\t' + raw_R1_reads + '\t' + raw_R1_bases + '\t' + raw_R2_reads + '\t' + raw_R2_bases + '\t' + unpaired_reads + '\t' + unpaired_bases + '\t' + Q20_Total + '\t' + Q30_Total + '\t' + Q20_R1_bp + '\t' + Q20_R2_bp + '\t' + Q20_Total_singles + '\t' + Q20_R1_percent + '\t' + Q20_R2_percent + '\t' + Q20_unpaired_percent + '\t' + Q30_R1_bp + '\t' + Q30_R2_bp + '\t' + Q30_Total_singles + '\t' + Q30_R1_percent + '\t' + Q30_R2_percent + '\t' + Q30_unpaired_percent + '\t' + Total_Sequenced_bp + '\t' + Trimmed_Sequenced_reads + '\t' + Total_Sequenced_reads
    Out.write(Line)
    Out.close()

def reads_compare(raw_read_file, trimd_file, outcome_file, busco):
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
    with open(outcome_file, "a") as tmp:
        tmp.write(outcome)

def check_trimmed_reads(aggr_trimd_stats, prefix, busco):
    """Check trimmed reads statistics and generate summary."""
    approved = f"\nPASSED: There are reads in {prefix} R1/R2 after trimming."
    failure = f"\nFAILED: There are 0 reads in {prefix} R1/R2 after trimming!"

    if int(aggr_trimd_stats["R1[reads]"].values[1]) > 0 and int(aggr_trimd_stats["R2[reads]"].values[1]) > 0:
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
    # Run FASTP
    FastP_QC_after(args.trimmed_json, args.single_json, args.out_trimd_counts, args.name)

    # compare trimd reads
    reads_compare(args.raw_read, args.out_trimd_counts, args.out_summary, args.busco)

if __name__ == '__main__':
    main()
