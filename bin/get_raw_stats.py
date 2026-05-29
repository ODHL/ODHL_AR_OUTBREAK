#!/usr/bin/env python3

import pandas as pd  # Import pandas for data manipulation and analysis
import os  # Import os for file path operations
import argparse  # Import argparse for command-line argument parsing
from datetime import date  # Import date for handling date operations
from argparse import ArgumentParser  # Import ArgumentParser for easier argument parsing

# Function to get the script version
# Adapted from Phoenix Pipeline
# Written by S. Sevilla
def get_version():
    return "1.0.0"

def parse_args():
    """Parse command-line arguments for the script."""
    parser = argparse.ArgumentParser(
        description="Collect and compare raw and trimmed read statistics to summarize QC results."
    )
    # Required argument for R1 stats file
    parser.add_argument("-r1", "--r1_stats", dest="r1_stats", required=True,
                        help="Text file with R1 stats, from q30.py script.")
    # Required argument for R2 stats file
    parser.add_argument("-r2", "--r2_stats", dest="r2_stats", required=True,
                        help="Text file with R2 stats, from q30.py script.")
    # Optional argument for trimmed reads statistics file
    parser.add_argument("-t", "--trimd_read", dest="trimd_read", default=None,
                        help="Path to the trimmed reads statistics file (optional).")
    # Required argument for sample name
    parser.add_argument("-n", "--name", dest="name", required=True, help="Sample name.")
    # Optional argument to include BUSCO checks
    parser.add_argument('-b', '--busco', dest="busco", action='store_true', default=False,
                        help='Include BUSCO checks.')
    parser.add_argument('-oS', '--out_summary', dest="out_summary", default=False,
                        help='output file name')    # Argument to show script version
    parser.add_argument('-oRC', '--out_raw_counts', dest="out_raw_counts", default=False,
                        help='output file name')    # Argument to show script version
    parser.add_argument('--version', action='version', version=get_version(),
                        help="Show the version of the script.")

    return parser.parse_args()  # Return the parsed arguments

def all_raw_stats(r1_stats, r2_stats, out_raw_counts, name):
    """Generates a summary output of raw read counts."""
    
    # Get raw statistics for R1 and R2
    raw_R1_reads, raw_R1_bases, Q20_R1_bp, Q20_R1_percent, Q30_R1_bp, Q30_R1_percent = get_raw_stats(r1_stats)
    raw_R2_reads, raw_R2_bases, Q20_R2_bp, Q20_R2_percent, Q30_R2_bp, Q30_R2_percent = get_raw_stats(r2_stats)

    # Write the raw statistics to the output file
    write_raw_stats(raw_R1_reads, raw_R1_bases, Q20_R1_bp, Q20_R1_percent, 
                    Q30_R1_bp, Q30_R1_percent, raw_R2_reads, raw_R2_bases, 
                    Q20_R2_bp, Q20_R2_percent, Q30_R2_bp, Q30_R2_percent, 
                    out_raw_counts, name)

def get_raw_stats(stats):
    """Extracts raw statistics from the provided stats file."""
    with open(stats) as f:
        lines = f.readlines()  # Read all lines from the stats file
        if len(lines) < 6:  # Ensure there are enough lines for expected stats
            raise ValueError(f"File {stats} does not contain enough lines for expected stats.")

        # Parse the statistics from the lines
        raw_reads = int(lines[0].strip().replace("total reads: ", ""))
        raw_bases = int(lines[1].strip().replace("total bases: ", ""))
        Q20_bp = int(lines[2].strip().replace("q20 bases: ", ""))
        Q30_bp = int(lines[3].strip().replace("q30 bases: ", ""))
        Q20_percent = str(round(float(lines[4].strip().replace("q20 percentage: ", "")) / 100, 4))
        Q30_percent = str(round(float(lines[5].strip().replace("q30 percentage: ", "")) / 100, 4))

    return raw_reads, raw_bases, Q20_bp, Q20_percent, Q30_bp, Q30_percent  # Return the extracted values

def write_raw_stats(raw_R1_reads, raw_R1_bases, Q20_R1_bp, Q20_R1_percent, 
                    Q30_R1_bp, Q30_R1_percent, raw_R2_reads, raw_R2_bases, 
                    Q20_R2_bp, Q20_R2_percent, Q30_R2_bp, Q30_R2_percent, 
                    out_raw_counts, name):
    """Creates a QC output file from parsed outputs of q30.py files."""
    with open(out_raw_counts, 'w') as f:
        # Write the header for the output file
        header = ('Name\tR1[reads]\tR1[bp]\tR2[reads]\tR2[bp]\tQ20_Total_[bp]\t'
                  'Q30_Total_[bp]\tQ20_R1_[bp]\tQ20_R2_[bp]\tQ20_R1_[%]\t'
                  'Q20_R2_[%]\tQ30_R1_[bp]\tQ30_R2_[bp]\tQ30_R1_[%]\t'
                  'Q30_R2_[%]\tTotal_Sequenced_[bp]\tTotal_Sequenced_[reads]\n')
        f.write(header)
        
        # Calculate totals
        Q20_Total = Q20_R1_bp + Q20_R2_bp
        Q30_Total = Q30_R1_bp + Q30_R2_bp
        Total_Sequenced_bp = raw_R1_bases + raw_R2_bases
        Total_Sequenced_reads = raw_R1_reads + raw_R2_reads
        
        # Write the calculated values to the output file
        line = (f"{name}\t{raw_R1_reads}\t{raw_R1_bases}\t{raw_R2_reads}\t{raw_R2_bases}\t"
                f"{Q20_Total}\t{Q30_Total}\t{Q20_R1_bp}\t{Q20_R2_bp}\t"
                f"{Q20_R1_percent}\t{Q20_R2_percent}\t{Q30_R1_bp}\t"
                f"{Q30_R2_bp}\t{Q30_R1_percent}\t{Q30_R2_percent}\t"
                f"{Total_Sequenced_bp}\t{Total_Sequenced_reads}\n")
        f.write(line)

def reads_compare(out_raw_counts, out_summary, trimd_file, busco, name):
    """Compare read statistics and generate summary."""
    # Load raw read stats into DataFrame
    aggr_read_stats = pd.read_csv(out_raw_counts, sep="\t") 

    # Check if there is a trimmed file
    if trimd_file:
        aggr_trimd_stats = pd.read_csv(trimd_file, sep="\t")  # Load trimmed read stats
        outcome = check_trimmed_reads(aggr_trimd_stats, name, busco)  # Check trimmed reads
    else:
        outcome = check_raw_reads(aggr_read_stats, name, busco)  # Check raw reads

    # Write the outcome to the summary file
    with open(out_summary, "a") as tmp:
        tmp.write(outcome)  # Append the outcome to the summary file

def check_trimmed_reads(aggr_trimd_stats, name, busco):
    """Check trimmed reads statistics and generate summary."""
    approved = f"\nPASSED: There are reads in {name} R1/R2 after trimming."  # Success message
    failure = f"\nFAILED: There are 0 reads in {name} R1/R2 after trimming!"  # Failure message
    
    # Check if both R1 and R2 have reads after trimming
    if aggr_trimd_stats["R1[reads]"].values[0] > 0 and aggr_trimd_stats["R2[reads]"].values[0] > 0:
        return approved  # Return success message if condition is met
    else:
        raw_stats = get_read_stats(aggr_trimd_stats, trimmed=True)  # Get raw stats if failed
        warning_count = write_synopsis(name, busco, *raw_stats)  # Write synopsis
        write_summary_line(name, busco, warning_count, "No reads after trimming!")  # Write summary line
        return failure  # Return failure message

def check_raw_reads(aggr_read_stats, name, busco):
    """Check raw reads statistics and generate summary."""
    approved = f"PASSED: Read pairs for {name} are equal."  # Success message
    failure = "FAILED: The number of reads in R1/R2 are NOT the same!"  # Failure message

    # Check if the number of reads in R1 and R2 are equal
    if aggr_read_stats["R1[reads]"].equals(aggr_read_stats["R2[reads]"]):
        return approved  # Return success message if condition is met
    else:
        raw_stats = get_read_stats(aggr_read_stats, trimmed=False)  # Get raw stats if failed
        warning_count = write_synopsis(name, busco, *raw_stats)  # Write synopsis
        write_summary_line(name, busco, warning_count, "Unequal number of reads in R1/R2!")  # Write summary line
        return failure  # Return failure message

def get_read_stats(aggr_read_stats, trimmed):
    """Extract statistics from the aggregated read stats."""
    length_R1 = str(aggr_read_stats["R1[bp]"].values[0])  # Length of R1 bases
    length_R2 = str(aggr_read_stats["R2[bp]"].values[0])  # Length of R2 bases
    reads = int(aggr_read_stats["Total_Sequenced_[reads]"].values[0])  # Total sequenced reads
    pairs = str(reads // 2)  # Calculate paired reads
    orphaned_reads = str(aggr_read_stats["Unpaired[reads]"].values[0]) if trimmed else str(0)  # Orphaned reads count
    Q30_R1_rounded = round((float(aggr_read_stats["Q30_R1_[%]"].values[0]) * 100), 2)  # Q30 for R1
    Q30_R2_rounded = round((float(aggr_read_stats["Q30_R2_[%]"].values[0]) * 100), 2)  # Q30 for R2
    
    return length_R1, length_R2, reads, pairs, Q30_R1_rounded, Q30_R2_rounded, orphaned_reads  # Return extracted values

def write_synopsis(name, busco, raw_length_R1, raw_length_R2, raw_reads, raw_pairs, raw_Q30_R1_rounded, raw_Q30_R2_rounded, trimd_file, trimd_length_R1, trimd_length_R2, trimd_reads, trimd_pairs, trimd_Q30_R1_rounded, trimd_Q30_R2_rounded, orphaned_reads):
    """Write a synopsis of the QC check results."""
    status = "FAILED"  # Initialize status
    warning_count = 0  # Initialize warning count
    Error = "Unequal number of reads in R1/R2!\n" if not trimd_file else "No reads after trimming!\n"  # Error message

    # Open the synopsis file for appending
    with open(f"{name}.synopsis", "a") as f:
        today = date.today()  # Get today's date
        f.write("---------- Checking " + sample_name + " for successful completion on ----------\n")
        f.write("Summarized                    : SUCCESS : " + str(today) + "\n")
        f.write("FASTQs                        : SUCCESS :  R1: " + raw_length_R1 + "bps R2: " + raw_length_R2 + "bps\n")
        
        # RAW_READ_COUNTS check
        if 1 <= raw_reads <= 1000000:  # Check for low individual read count
            f.write(f"RAW_READ_COUNTS               : WARNING : Low individual read count before trimming: {raw_reads} ({raw_pairs} paired reads)\n")
            warning_count += 1
        elif raw_reads <= 0:  # Check for no reads
            f.write(f"RAW_READ_COUNTS               : FAILED  : No individual read count before trimming: {raw_reads} ({raw_pairs} paired reads)\n")
        else:
            f.write(f"RAW_READ_COUNTS               : SUCCESS : {raw_reads} individual reads found in sample ({raw_pairs} paired reads)\n")

        # Q30 checks
        if raw_Q30_R1_rounded < 90:  # Check Q30 for R1
            f.write(f"RAW_Q30_R1%                   : WARNING : Q30_R1% at {raw_Q30_R1_rounded}% (Threshold is 90%)\n")
            warning_count += 1
        else:
            f.write(f"RAW_Q30_R1%                   : SUCCESS : Q30_R1% at {raw_Q30_R1_rounded}% (Threshold is 90%)\n")

        if raw_Q30_R2_rounded < 70:  # Check Q30 for R2
            f.write(f"RAW_Q30_R2%                   : WARNING : Q30_R2% at {raw_Q30_R2_rounded}% (Threshold is 70%)\n")
            warning_count += 1
        else:
            f.write(f"RAW_Q30_R2%                   : SUCCESS : Q30_R2% at {raw_Q30_R2_rounded}% (Threshold is 70%)\n")

        # Trimming details
        if trimd_file is None:  # If no trimming performed
            f.write("TRIMMED_READ_COUNTS           : FAILED  : No trimming performed.\n")
            f.write("TRIMMED_Q30_R1%               : FAILED  : No trimming performed.\n")
            f.write("TRIMMED_Q30_R2%               : FAILED  : No trimming performed.\n")
        else:
            f.write("TRIMMED_READ_COUNTS           : FAILED  : No individual read count after trimming!\n")

        # Additional failure reasons
        f.write("---------- " + sample_name + " completed as " + status + " ----------\n")

    return warning_count  # Return count of warnings

def write_summary_line(name, busco, warning_count, error):
    """Write summary statistics to a TSV file."""
    column_names = ['ID', 'Auto_QC_Outcome', 'Warning_Count', 'Auto_QC_Failure_Reason']
    data = [[name, 'FAIL', warning_count, error]]  # Prepare data for the summary line
    df = pd.DataFrame(data, columns=column_names)  # Create DataFrame from data
    df.to_csv(f"{name}_summaryline.tsv", sep="\t", index=False)  # Write to TSV file

def main():
    """Main function to run the script."""
    args = parse_args()  # Parse command-line arguments

    # run raw process
    all_raw_stats(args.r1_stats, args.r2_stats, args.out_raw_counts, args.name)  # Collect raw stats
    reads_compare(args.out_raw_counts, args.out_summary, args.trimd_read, args.busco, args.name)  # Compare read stats

if __name__ == '__main__':
    main()  # Execute the main function when the script is run
