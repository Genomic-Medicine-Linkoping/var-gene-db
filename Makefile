SHELL = /bin/bash
.ONESHELL:
#.SHELLFLAGS := -eu -o pipefail -c
.SHELLFLAGS := -e -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

.PHONY: all

CURRENT_CONDA_ENV_NAME = notebook
# Note that the extra activate is needed to ensure that the activate floats env to the front of PATH
CONDA_ACTIVATE = source $$(conda info --base)/etc/profile.d/conda.sh ; conda activate ; conda activate $(CURRENT_CONDA_ENV_NAME)

# Exonerate utilities: https://www.ebi.ac.uk/about/vertebrate-genomics/software/exonerate
FASTACLEAN = $$(conda info --base)/envs/$(CURRENT_CONDA_ENV_NAME)/bin/fastaclean
FASTADIFF = $$(conda info --base)/envs/$(CURRENT_CONDA_ENV_NAME)/bin/fastadiff
# Seqkit utilities: https://bioinf.shenwei.me/seqkit/usage/
SEQKIT = $$(conda info --base)/envs/$(CURRENT_CONDA_ENV_NAME)/bin/seqkit
# Raw and intermediary fasta files
RAW_SEQS = raw/Diagnostic_genes.fa
DIAG_GENES = proc/diagnostic_genes.fa
TEMP_DIAG_GENES = temp_diagnostic_genes.fa
# Phenotype data
RAW_PHENOS = raw/Diagnostic_genes_phenotypes.tsv
PHENOS = proc/phenotypes.tsv
# Final fasta files
CODING = final/coding.fa
NONC = final/non-coding.fa
BOTH = final/coding_non-coding.fa

all: prepare_genes prepare_phenos exec_ipynbs archive_ipynbs
	@echo "Created all intermediary and final files."

## exec_ipynbs: Run Jupyter notebooks in order to produce final files
exec_ipynbs:
	$(CONDA_ACTIVATE) ; \
	jupyter nbconvert --inplace --to notebook --execute bin/add_phenos_to_fasta.ipynb ; \
	jupyter nbconvert --inplace --to notebook --execute bin/gather_seqs.ipynb

## archive_ipynbs: Create rendered files for archiving purposes
archive_ipynbs:
	$(CONDA_ACTIVATE) ; \
	jupyter nbconvert --to html bin/add_phenos_to_fasta.ipynb bin/add_phenos_to_fasta.ipynb ; \
	jupyter nbconvert --to markdown bin/add_phenos_to_fasta.ipynb bin/add_phenos_to_fasta.ipynb ; \
	jupyter nbconvert --to html bin/gather_seqs.ipynb bin/gather_seqs.ipynb ; \
	jupyter nbconvert --to markdown bin/gather_seqs.ipynb bin/gather_seqs.ipynb
	mv bin/*.{md,html} proc/

## prepare_genes: Clean multifasta file and save it to proc/ directory
## 1. Clean raw fasta file
## 2. Remove automatically added ":filter.+" text from fasta headers
## 3. Remove duplicate sequences
## 4. Rename duplicate fasta headers
## 5. Remove parentheses from fasta headers
## 6. Remove from renamed duplicated fasta headers difficult to parse duplicated
## information and exchange it with "dupID"-text
prepare_genes:
	@($(CONDA_ACTIVATE) ; $(FASTACLEAN) -f $(RAW_SEQS) | \
	$(SEQKIT) replace -p ":filter.+" | \
	$(SEQKIT) rmdup --by-seq | \
	$(SEQKIT) rename -n | \
	tr -d '()' | \
	tr '/' '_' | \
	$(SEQKIT) replace -p '(^.+)\s\S+' -r '$$1 dupID' > $(DIAG_GENES))

## prepare_phenos: Remove duplicate rows, '(',')' and '/' from raw phenotypes csv
prepare_phenos:
	@(tail -n +2 $(RAW_PHENOS) | \
	sort | \
	uniq | \
	tr -d '()' | \
	tr '/' '_' > $(PHENOS)) 
	@(sed -i '1 i\
	name\tphenotype' $(PHENOS)) # Insert tsv header

## check_files: Print out basic information about the raw data
check_files:
	file $(BOTH) $(RAW_SEQS) $(RAW_PHENOS)

## find_dups: Compare the fasta files
find_dups: prepare_genes
	@($(CONDA_ACTIVATE) ; $(FASTACLEAN) -f $(RAW_SEQS) | \
	$(SEQKIT) replace -p ":filter.+" | \
	$(SEQKIT) rename -n > $(TEMP_DIAG_GENES) ; \
	$(FASTADIFF) -1 $(TEMP_DIAG_GENES) -2 $(DIAG_GENES) ; \
	rm -f $(TEMP_DIAG_GENES))

## sanity_check: Do some sanity checks
sanity_check:
	@echo
	# Check number of unique gene IDs in raw and processed files
	cut -f 1 -d, $(RAW_PHENOS) | sort | uniq | wc -l
	cut -f 1 -d, $(PHENOS) | sort | uniq | wc -l
	
	@echo
	# Check number of fasta headers in all fasta files
	grep --count -E "^>.+" $(RAW_SEQS)
	grep --count -E "^>.+" $(DIAG_GENES)
	grep --count -E "^>.+" $(CODING)
	grep --count -E "^>.+" $(NONC)
	grep --count -E "^>.+" $(BOTH)
	
	@echo
	# Check if removing of duplicates worked
	$(CONDA_ACTIVATE) ; $(SEQKIT) rmdup --by-seq $(RAW_SEQS) | \
	grep --count -E "^>.+" ; \
	$(SEQKIT) rmdup --by-seq $(BOTH) | \
	grep --count -E "^>.+"
	
	@echo
	# Compare raw headers to phenotype-gene csv's IDs
	comm --total <(grep -E '^>.+' $(RAW_SEQS) | sed 's/^>//' | sort | uniq) \
	<(tail -n +2 $(RAW_PHENOS) | cut -f 1 -d, | sort | uniq) | \
	tee >(tail -n 5) >(head -n 5; cat > /dev/null) > /dev/null

## clean: Remove intermediary files
clean:
	rm -f proc/*

## help: Show this message
help:
	@grep '^##' ./Makefile
