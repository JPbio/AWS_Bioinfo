#!/bin/bash

#by JPbio 2024

###### ATTENTION: #######
#to control and access the S3 buckets and instance properties and metadatas from inside the linux prompt accessed via ssh...
#... the IAM policies to allow it must be set and attached to the instance previously
#... you also need to install awscli set the 'aws configure' with your credentials and instance region;
#... it is also easy to get the instance metadata if you install amazon-ec2-utils, I'm having problems with the other appoaches to get the metadata
#... I'll make an entire folder about instance metadata and operating S3 buckets inside the instance accessed via ssh;  
########################


# Help function to display usage instructions
function display_help {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -l, --input-file     Specify the input file containing a list of SRA accessions files to process"
  echo "  -p, --path           Specify the destination path in S3 (default: s3://trimlibs/albopictus/)"
  echo "  --stop               Stop the EC2 instance after script execution"
  echo "  -h, --help           Display this help message"
}

# Default values
path="s3://"
stop_instance=false

# Parse command line options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -l|--input-file) input_file="$2"; shift ;;
    -p|--path) path="$2"; shift ;;
    --stop) stop_instance=true ;;
    -h|--help) display_help; exit 0 ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# Check if input file is provided
if [ -z "$input_file" ]; then
  echo "Input file not provided. Use the -l or --input-file option to specify the input file." >&2
  display_help
  exit 1
fi

#activating a previously defined defined conda enviorement 
#conda init
#conda activate bioinformatics

# Main processing loop
while IFS= read -r p; do
  fasterq-dump "$p"
  trim_galore --fastqc --length 18 --trim-n --max_n 0 -j 7 --dont_gzip "${p}.fastq"
  rm -f "${p}.fastq"
  seqtk seq -A "${p}_trimmed.fq" > "${p}_trimmed.fasta"
  rm -f "${p}_trimmed.fq"
  gzip "${p}_trimmed.fasta"
  aws s3 cp "${p}_trimmed.fasta.gz" "${path}${p}_trimmed.fasta.gz"
  aws s3 cp "${p}.fastq_trimming_report.txt" "${path}${p}.fastq_trimming_report.txt"
  aws s3 cp "${p}_trimmed_fastqc.zip" "${path}${p}_trimmed_fastqc.zip"
  rm -f "${p}"*
  echo "$p is done"
done < "$input_file"

# Stop the instance if --stop option is provided
if [ "$stop_instance" = true ]; then
  ### Get the id of the EC2 instance
  # instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id) # too many cnditions to work
  instance_id=$(ec2-metadata -i | cut -f2 -d ":" | sed -e 's/^ //g') # needs amazon-ec2-utils installed
  
  ### Get the region of the EC2 instance
  #region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')  #too many conditions to work
  region=$(ec2-metadata -z | cut -f2 -d ":" | sed -e 's/^ //g' | sed -e 's/[a-z]$//g') # needs amazon-ec2-utils installed
 
  ### stopping the instace
  sudo aws ec2 stop-instances --instance-ids "$instance_id" --region "$region" #need to fix the need of sudo
fi
