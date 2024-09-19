#!/bin/bash

# ------------------------------------------------------------------------------------
# v1.0 by Colette L. Picard
# 08/25/2016
# ------------------------------------------------------------------------------------

# Usage:
# ends_analysis_basecomp.sh [options] -i [regions.bed/seqs.fa] -g genome.fa -o outprefix

# -------------------------
# Version history:
# v.1.0: initial build - 08/25/2016
# -------------------------

# See below for description.

# Description printed when "help" option specified:
read -d '' usage <<"EOF"
v1.0 by Colette Picard, 08/25/2016

Modified ends analysis script specifically designed to plot the average A,C,T,G composition
at positions within and around a set of regions of interest. Uses some of the ends_analysis
scripts and is strand-aware.
					
Usage:
ends_analysis_basecomp.sh [options] -r regions.bed -g genome.fa -o outprefix

User-specified options:
Required arguments:
	-r regions : a set of BED intervals (features)
	-g genome : genome in FASTA format
	-o outprefix : prefix for output files
Additional options:
	-s path_to_scripts : path to folder containing all required helper scripts (see list below) [$scriptDir]
	-O numOut : number of bases outside of feature to plot at each end (see diagram above) [1000]
	-I numIn : number of bases inside of feature to plot at each end (see diagram above) [1000]
	-u yupper : set upper limit for y axis manually in output plot [1]
	-t title : title for output plot [""]
Flag options:
	-W : output plot as a weblogo (see http://weblogo.threeplusone.com/manual.html#CLI) instead of line graph [weblogo=false]
	-S : don't delete the FASTA intermediate file (left and right sides will be pasted together) [keepfasta=false]
	-R : allow overwrite of existing output files (WARNING: all files currently in outdir will be deleted!) [overwrite=false]
	-0 : checks that all required programs installed on PATH and all required helper scripts can be located, then exits without running
	-h : prints this version and usage information
	
Must be in path_to_scripts:
	- ends_analysis_process_intersect.py - by Colette L Picard
	- ends_analysis_make_plot.R - by Colette L Picard
Must be installed on your PATH:
	- bedtools (v2.23.0)
		
------------------------------------------------------------------------------------

EOF

[[ $# -eq 0 ]] && { printf "%s\n" "$usage"; exit 0; } 		# if no user-supplied arguments, print usage and exit

# ----------------------
# Get user-specified arguments
# ----------------------

# Initiate environment
scriptDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )	# location of this script 
workdir=$( pwd )											# working directory

# Required arguments:
# ----------------------
regions=""							# a set of BED intervals (features)
genome=""							# genome in FASTA format
outprefix=""							# prefix for output files

# Additional options:
# ----------------------
path_to_scripts="$scriptDir"							# path to folder containing all required helper scripts (see list below)
numOut=1000								# number of bases outside of feature to plot at each end (see diagram above)
numIn=1000								# number of bases inside of feature to plot at each end (see diagram above)
yupper=1								# set upper limit for y axis manually in output plot
title=""							# title for output plot

# Flag options:
# ----------------------
weblogo=false							# output plot as a weblogo (see http://weblogo.threeplusone.com/manual.html#CLI) instead of line graph
keepfasta=false							# don't delete the FASTA intermediate file (left and right sides will be pasted together)
overwrite=false							# allow overwrite of existing output files (WARNING: all files currently in outdir will be deleted!)

checkdep=false

# ----------------------
while getopts "r:g:o:s:O:I:u:t:WSR0h" opt; do
	case $opt in
		r)	# a set of BED intervals (features)
			regions="$OPTARG"
			;;
		g)	# genome in FASTA format
			genome="$OPTARG"
			;;
		o)	# prefix for output files
			outprefix="$OPTARG"
			;;
		s)	# path to folder containing all required helper scripts (see list below)
			path_to_scripts="$OPTARG"
			;;
		O)	# number of bases outside of feature to plot at each end (see diagram above)
			numOut="$OPTARG"
			;;
		I)	# number of bases inside of feature to plot at each end (see diagram above)
			numIn="$OPTARG"
			;;
		u)	# set upper limit for y axis manually in output plot
			yupper="$OPTARG"
			;;
		t)	# title for output plot
			title="$OPTARG"
			;;
		W)	# output plot as a weblogo (see http://weblogo.threeplusone.com/manual.html#CLI) instead of line graph
			weblogo=true
			;;
		S)	# don't delete the FASTA intermediate file (left and right sides will be pasted together)
			keepfasta=true
			;;
		R)	# allow overwrite of existing output files (WARNING: all files currently in outdir will be deleted!)
			overwrite=true
			;;
		0)	# check dependencies ok then exit
			checkdep=true
			;;
		h)	# print usage and version information to stdout and exit
			echo "$usage"
			exit 0
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done

# Check that all programs required on PATH are installed
# ----------------------
command -v bedtools >/dev/null 2>&1 || { echo "Error: bedtools is required on PATH but was not found"; exit 1; }

# Check that required files are in path_to_scripts (set path to this location with option -s)
# ----------------------
[ ! -f "$path_to_scripts/ends_analysis_process_intersect.py" ] && { echo "Error: could not find required file ends_analysis_process_intersect.py in provided folder (${path_to_scripts})"; exit 1; }
[ ! -f "$path_to_scripts/ends_analysis_make_plot.R" ] && { echo "Error: could not find required file ends_analysis_make_plot.R in provided folder (${path_to_scripts})"; exit 1; }

# Done checking all requirements. Stop here if -0 flagged.
# ----------------------
"$checkdep" && exit 0

# Check all required inputs are provided
# ----------------------
[ -z "$regions" ] && { echo "Error: -r regions is a required argument (a set of BED intervals (features))"; exit 1; }
[ -z "$genome" ] && { echo "Error: -g genome is a required argument (genome in FASTA format)"; exit 1; }
[ -z "$outprefix" ] && { echo "Error: -o outprefix is a required argument (prefix for output files)"; exit 1; }

# Check all inputs exist and are nonempty
# ----------------------
[ -f "$regions" ] || { echo "Error: could not open regions file $regions"; exit 1; }
[ -f "$genome" ] || { echo "Error: could not open genome file $genome"; exit 1; }
[ -s "$regions" ] || { echo "Error: regions file $regions is empty"; exit 1; }
[ -s "$genome" ] || { echo "Error: genome file $genome is empty"; exit 1; }

# Check weblogo installed if using -W option and settings ok
# ----------------------
if [ "$weblogo" = "true" ]; then
	totlen=$(( $numIn + $numOut ))
	[ "$totlen" -gt "20" ] && { echo "Creating a weblogo is only allowed when the sum of -I and -O is <= 20; current sum is $totlen"; exit 1; }
	[ ! -f "$path_to_scripts/weblogo/weblogo" ] && { echo "Error: could not find required file weblogo/weblogo in provided folder (${path_to_scripts})"; exit 1; }
fi

# Output user-derived options to stdout and to log file
# ----------------------
time_start=$(date)	# time run was started
time_ss=$(date +%s)	# time run was started (in seconds)
echo "Running ends_analysis_basecomp.sh v1.0 (08/25/2016):"
echo "Run start on: $time_start"
echo "-------------------------"
echo "Regions file: $regions"
echo "Genome file: $genome"
echo "Output file prefix: $outprefix"
echo "-------------------------"
echo "Number of bases outside gene: $numOut"
echo "Number of bases inside gene: $numIn"
echo "-------------------------"
echo ""

# ----------------------
# Step 1: from regions file, make BED file with all intervals
# ----------------------
echo "Getting intervals for analysis..."

awk -F$'\t' -v o="$numOut" -v i="$numIn" '{OFS=FS} {if ($6=="+") {mdpt=int($2+(($3-$2)/2)); if ($2-o > 0) {if ($2+i > mdpt) { print $1,$2-o,mdpt,$4,$5,$6 } else {print $1,$2-o,$2+i,$4,$5,$6}}}}' "$regions" > "${outprefix}_ltreg.bed"
awk -F$'\t' -v o="$numOut" -v i="$numIn" '{OFS=FS} {if ($6=="+") {mdpt=int($2+(($3-$2)/2)); alt=$3-i; {if (($3-$2) % 2 == 1) {mdpt=mdpt+1}}; if (alt < mdpt) { print $1,mdpt,$3+o,$4,$5,$6 } else {print $1,alt,$3+o,$4,$5,$6}}}' "$regions" > "${outprefix}_rtreg.bed"
awk -F$'\t' -v o="$numOut" -v i="$numIn" '{OFS=FS} {if ($6=="-") {mdpt=int($2+(($3-$2)/2)); if ($2-o > 0) {if ($2+i > mdpt) { print $1,$2-o,mdpt,$4,$5,$6 } else {print $1,$2-o,$2+i,$4,$5,$6}}}}' "$regions" >> "${outprefix}_rtreg.bed"
awk -F$'\t' -v o="$numOut" -v i="$numIn" '{OFS=FS} {if ($6=="-") {mdpt=int($2+(($3-$2)/2)); alt=$3-i; {if (($3-$2) % 2 == 1) {mdpt=mdpt+1}}; if (alt < mdpt) { print $1,mdpt,$3+o,$4,$5,$6 } else {print $1,alt,$3+o,$4,$5,$6}}}' "$regions" >> "${outprefix}_ltreg.bed"

# ----------------------
# Step 2: extract sequences from genome
# ----------------------
echo "Extracting corresponding sequences from genome..."
bedtools getfasta -s -fi "$genome" -bed "${outprefix}_ltreg.bed" -name -fo "${outprefix}_ltreg.fa"
[ $? != 0 ] && { echo "Error: bedtools getfasta failed"; exit 1; }
bedtools getfasta -s -fi "$genome" -bed "${outprefix}_rtreg.bed" -name -fo "${outprefix}_rtreg.fa"
[ $? != 0 ] && { echo "Error: bedtools getfasta failed"; exit 1; }
rm "${outprefix}_ltreg.bed" "${outprefix}_rtreg.bed"

# ----------------------
# Step 3: converting sequences to per-position fraction A,T,G,C
# ----------------------
echo "Getting per-position base information..."

awk -F$'\t' '{OFS=FS} { if ($0 !~ /^>/) {
	split($0, ll, "")
	for (i=1; i <= length($0); i++) {
		tot[i]+=1
		if (ll[i] == "A") {A[i]+=1} else {A[i]+=0}
		if (ll[i] == "T") {T[i]+=1} else {T[i]+=0}
		if (ll[i] == "G") {G[i]+=1} else {G[i]+=0}
		if (ll[i] == "C") {C[i]+=1} else {C[i]+=0}
	}
}} END {
	for (i=1; i <= length(A); i++) {
		print i,A[i]/tot[i],"A"
		print i,T[i]/tot[i],"T"
		print i,G[i]/tot[i],"G"
		print i,C[i]/tot[i],"C"
	}
}' "${outprefix}_ltreg.fa" > "${outprefix}_ltreg_perpos.txt"
[ $? != 0 ] && { echo "Error: failed to get per-base information"; exit 1; }

maxL=$( tail -1 "${outprefix}_ltreg_perpos.txt" | cut -f1 )		# max position

awk -F$'\t' -v s="$maxL" '{OFS=FS} { if ($0 !~ /^>/) {
	split($0, ll, "")
	for (i=1; i <= length($0); i++) {
		tot[i]+=1
		if (ll[i] == "A") {A[i]+=1} else {A[i]+=0}
		if (ll[i] == "T") {T[i]+=1} else {T[i]+=0}
		if (ll[i] == "G") {G[i]+=1} else {G[i]+=0}
		if (ll[i] == "C") {C[i]+=1} else {C[i]+=0}
	}
}} END {
	for (i=1; i <= length(A); i++) {
		print i+s,A[i]/tot[i],"A"
		print i+s,T[i]/tot[i],"T"
		print i+s,G[i]/tot[i],"G"
		print i+s,C[i]/tot[i],"C"
	}
}' "${outprefix}_rtreg.fa" > "${outprefix}_rtreg_perpos.txt"
[ $? != 0 ] && { echo "Error: failed to get per-base information"; exit 1; }

if [ "$weblogo" = "true" ]; then
	# convert data into transfac position weight matrix format
	echo "ID Matrix" > "${outprefix}_pwm.txt"
	echo "PO	A	C	G	T" >> "${outprefix}_pwm.txt"
	awk -F$'\t' '{OFS=FS} { 
		pos[$1] = 1
		if ($3 == "A") { A[$1]=$2 }
		if ($3 == "T") { T[$1]=$2 }
		if ($3 == "G") { G[$1]=$2 }
		if ($3 == "C") { C[$1]=$2 }
	} END {
		for (i in pos) {
			print i,A[i],C[i],G[i],T[i]
		}
	}' "${outprefix}_ltreg_perpos.txt" | sort -k1n,1 >> "${outprefix}_pwm.txt"
	echo "$(( $maxL + 1 ))	0	0	0	0" >> "${outprefix}_pwm.txt"
	
	awk -F$'\t' -v s="$(( $maxL + 1 ))" '{OFS=FS} { 
		pos[$1] = 1
		if ($3 == "A") { A[$1]=$2 }
		if ($3 == "T") { T[$1]=$2 }
		if ($3 == "G") { G[$1]=$2 }
		if ($3 == "C") { C[$1]=$2 }
	} END {
		for (i in pos) {
			print i+s,A[i],C[i],G[i],T[i]
		}
	}' "${outprefix}_rtreg_perpos.txt" | sort -k1n,1 >> "${outprefix}_pwm.txt"
	
else
	cat "${outprefix}_ltreg_perpos.txt" "${outprefix}_rtreg_perpos.txt" | sort -k3,3 -k1n,1 > "${outprefix}_perpos.txt"
fi

if [ "$keepfasta" = "true" ]; then
	echo "Keeping fasta file..."
	paste "${outprefix}_ltreg.fa" "${outprefix}_rtreg.fa" | sed 's/\t>.*$//' | sed 's/\t//' > "${outprefix}_sequences.fa"
fi
rm "${outprefix}_ltreg_perpos.txt" "${outprefix}_rtreg_perpos.txt" "${outprefix}_ltreg.fa" "${outprefix}_rtreg.fa" 


# ----------------------
# Step 4: make plot
# ----------------------
echo "Plotting results..."

if [ "$weblogo" = "true" ]; then

	num=$(( $(( $numIn + $numOut )) * 2 + 1 ))
	annot="-${numOut}bp"
	for ((i=1;i<"$num";++i)); do
		if [ "$i" -eq $(( $numOut - 1)) ]; then
			annot="${annot},-1bp"
		elif [ "$i" -eq $(( $numOut + $numIn - 1 )) ]; then
			annot="${annot},+${numIn}bp"
		elif [ "$i" -eq $(( $numOut + $numIn + 1 )) ]; then
			annot="${annot},-${numIn}bp"
		elif [ "$i" -eq $(( $numOut + 2*${numIn} + 1 )) ]; then
			annot="${annot},+1bp"
		elif [ "$i" -eq $(( $num - 1 )) ]; then
			annot="${annot},+${numOut}bp"
		else
			annot="${annot},"
		fi
	 done

	"$path_to_scripts/weblogo/weblogo" --format PNG -D "transfac" -A "dna" -U "probability" -s "large" -t "$title" -c "classic" --fineprint "" --annotate "$annot" -n 41 -f "${outprefix}_pwm.txt" > "${outprefix}_plot.png"
	[ $? != 0 ] && { echo "Error: weblogo failed"; exit 1; }
else
	$path_to_scripts/ends_analysis_make_plot.R "${outprefix}_perpos.txt" "$yupper" "% of bases" "$title" "$outprefix" "$numIn" "$numOut" 1 --colors "forestgreen dodgerblue gold firebrick" > "${outprefix}_log_plot.txt"
	[ $? != 0 ] && { echo "Error: ends_analysis_make_plot failed, see ${outprefix}_log_plot.txt"; exit 1; }

	rm "${outprefix}_log_plot.txt"
fi






























