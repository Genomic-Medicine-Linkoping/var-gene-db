SHELL = /bin/bash

CURRENT_CONDA_ENV_NAME = var-genes-ro
# Note that the extra activate is needed to ensure that the activate floats env to the front of PATH
CONDA_ACTIVATE = source $$(conda info --base)/etc/profile.d/conda.sh ; conda activate ; conda activate $(CURRENT_CONDA_ENV_NAME)

FASTACLEAN = ~/miniconda3/envs/var-genes-ro/bin/fastaclean
FASTADIFF = ~/miniconda3/envs/var-genes-ro/bin/fastadiff
SEQKIT = ~/miniconda3/envs/var-genes-ro/bin/seqkit
DIAG_GENES = proc/diagnostic_genes.fa
TEMP_DIAG_GENES = temp_diagnostic_genes.fa
RAW_PHENOS = raw/Diagnostic_genes_v3_phenotypes.csv
RAW_SEQS = raw/Diagnostic_genes_v3.fa
CODING = coding.fa
NONC = non-coding.fa
BOTH = coding_non-coding.fa
PHENOS = proc/phenotypes.csv

prepare_genes:
	@($(CONDA_ACTIVATE) ; $(FASTACLEAN) -f raw/Diagnostic_genes_v3.fa | \
	$(SEQKIT) replace -p ":filter.+" | \
	$(SEQKIT) rmdup --by-seq | \
	$(SEQKIT) rename -n | \
	$(SEQKIT) replace -p '(^.+)\s\S+' -r '$$1 dupID' > $(DIAG_GENES))

check_files:
	file $(BOTH) $(RAW_SEQS) $(RAW_PHENOS)

find_dups:
	@($(CONDA_ACTIVATE) ; $(FASTACLEAN) -f raw/Diagnostic_genes_v3.fa | \
	$(SEQKIT) replace -p ":filter.+" | \
	$(SEQKIT) rename -n > $(TEMP_DIAG_GENES) ; \
	$(FASTADIFF) -1 $(TEMP_DIAG_GENES) -2 $(DIAG_GENES) ; \
	rm -f $(TEMP_DIAG_GENES))

remove_dup_phenos:
	# Remove duplicate entries
	tail -n +2 $(RAW_PHENOS) | sort | uniq > $(PHENOS)
	# Insert csv header
	sed -i '1 i\
	name,phenotype' $(PHENOS)

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

clean:
	rm -f proc/*
