# Setup 
## Setup for differential expression analysis
library(DESeq2)
library(org.Mm.eg.db)
library(biomaRt)

ensembl <- useMart("ensembl",dataset="mmusculus_gene_ensembl")
data_path <- "D:/Lina/Documents/share/mouse/hisat2_alt/"
setwd(data_path)

# Differential Expression Analysis
## Read in expression data, make conversions to count matrices

### Read in expression data calculated by StringTie
pheno_data <- read.table("180711Ess_phenodata.csv", header=TRUE, sep=",")
count_data <- read.table("gene_count_matrix.csv", header=TRUE, sep=",", row.names=1)

### Create readable gene count matrix
gene_names <- getBM(c("ensembl_gene_id", "external_gene_name"),
                      filters="ensembl_gene_id",
                      values=rownames(count_data),
                      mart=ensembl)
colnames(gene_names) <- c('ensembl_id','gene_name')
gene_set <- setNames(as.list(gene_names$gene_name), as.list(gene_names$ensembl_id))

gene_list <- lapply(rownames(count_data), function(id) {
  if (id %in% gene_names$ensembl_id) {
    return(gene_set[[id]])
  }
  return(".")
})

readable <- cbind(unlist(gene_list), rownames(count_data), count_data)
colnames(readable) <- c("gene_name", "ensembl_id", colnames(count_data))

### Cleanup: remove unnamed genes and duplicates
readable <- readable[readable$gene_name != ".",]   # remove unnamed genes
dups <- readable[duplicated(readable$gene_name) | duplicated(readable$gene_name, fromLast = TRUE),]
dups <- dups[order(dups$gene_name),]
write.csv(dups, "duplicates.csv", row.names=FALSE)

write.csv(readable, "gene_count_matrix_readable.csv", row.names=FALSE)

## Function for DESeq analysis and output
### Differential expression pairs
### By sex: DMSO, DMSO+TC, AFB1, AFB1+TC
### By TC: DMSO(M), DMSO(F), AFB1(M), AFB1(F)
valid.comp = c('sex', 'TCPOBOP')
valid.treat = c('DMSO', 'DMSO+TC', 'AFB1', 'AFB1+TC')
valid.sex = c('M', 'F')

### For TCPOBOP addition comparisons, input values for exp.treat must be the non-TC treatment value.
### e.g. "DMSO" instead of "DMSO+TC".
dea.group <- function(inp.dds, exp.comp, exp.treat, exp.sex=NA) {
  if (exp.comp == 'sex') {
    dds.sort <- inp.dds[,inp.dds$treatment == exp.treat]
    dds.sort$sex <- relevel(dds.sort$sex, ref="M")
    design(dds.sort) <- ~sex
    filename <- paste(paste("de", tolower(exp.comp), tolower(exp.treat), sep="_"), ".csv", sep="")
  } else if (exp.comp == 'TCPOBOP') {
    if (is.na(exp.sex)) {
      stop("TCPOBOP comparisons must specify sex!")
    }
    treat.tc <- paste(exp.treat, "TC", sep="+")
    dds.sort <- inp.dds[,inp.dds$sex == exp.sex]
    dds.sort <- dds.sort[,(dds.sort$treatment == exp.treat) | (dds.sort$treatment == treat.tc)]
    dds.sort$treatment <- droplevels(dds.sort$treatment)
    dds.sort$treatment <- relevel(dds.sort$treatment, ref=exp.treat)
    design(dds.sort) <- ~treatment
    filename <- paste(paste("de", "tc", paste(tolower(exp.treat), tolower(exp.sex), sep=""), sep="_"), ".csv", sep="")
  } else {
    stop(paste("Input variable", exp.comp, "for exp.comp is invalid! Must be sex or TCPOBOP."))
  }
  
  dds.sort <- DESeq(dds.sort)
  res.dds <- results(dds.sort)
  res.dds <- res.dds[order(res.dds$padj),]

  geneIDs.dds <- rownames(res.dds)
  geneNames.dds <- lapply(geneIDs.dds, function(id) {
    if (id %in% gene_names$ensembl_id) {
      return(gene_set[[id]])
    }
    return(".")
  })
  
  out.dds <- cbind(unlist(geneNames.dds), geneIDs.dds, res.dds)
  colnames(out.dds) <- c("gene_name", "gene_id", colnames(res.dds))
  out.dds <- out.dds[!is.na(out.dds$padj),]

  write.csv(out.dds, file=filename, row.names=FALSE)
  return(out.dds)
}

## Run DESeq2 on experimental groups
### All data, no design specified
dds <- DESeqDataSetFromMatrix(countData=count_data, colData=pheno_data, design=~1)

### Filter to remove low-abundance genes
keep.rows <- rowSums(counts(dds)) >= 10
dds <- dds[keep.rows,]

### Data by design and treatment group
### By sex
dds.sex_dmsona <- dea.group(dds, "sex", "DMSO")
dds.sex_dmsotc <- dea.group(dds, "sex", "DMSO+TC")
dds.sex_afb1na <- dea.group(dds, "sex", "AFB1")
dds.sex_afb1tc <- dea.group(dds, "sex", "AFB1+TC")

### By TCPOBOP addition
dds.tc_dmsom <- dea.group(dds, "TCPOBOP", "DMSO", "M")
dds.tc_dmsof <- dea.group(dds, "TCPOBOP", "DMSO", "F")
dds.tc_afb1m <- dea.group(dds, "TCPOBOP", "AFB1", "M")
dds.tc_afb1f <- dea.group(dds, "TCPOBOP", "AFB1", "F")
