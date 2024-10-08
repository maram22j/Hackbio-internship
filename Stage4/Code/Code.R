---
title: "R Notebook"
output: html_notebook
---

This is an [R Markdown](http://rmarkdown.rstudio.com) Notebook. When you execute code within the notebook, the results appear beneath the code. 

Try executing this chunk by clicking the *Run* button within the chunk or by placing your cursor inside it and pressing *Ctrl+Shift+Enter*. 

```{r}
#Load the required Libraries
library("TCGAbiolinks")
library("SummarizedExperiment")
library(dplyr)
library(tidyr)
library(ggplot2)
library(EnhancedVolcano)
library("gplots")
library(org.Hs.eg.db)
library(reshape2)

#-----------------------------------------------------Data extraction and preprocessing ---------------------------------------------
#1. Get project Summary to get project information
getProjectSummary("TCGA-LGG") # it provides details such as number of files, type of data available and no. of cases

#1.1Query for obataing the expression data for LGG samples
lgg_query <- GDCquery(
  project = "TCGA-LGG",
  data.category = "Transcriptome Profiling",
  data.type = "Gene Expression Quantification",
  sample.type = "Primary Tumor")

#1.2Download the data
GDCdownload(lgg_query)

#1.3Prepare the data
lgg.data<- GDCprepare(lgg_query)
table(lgg.data$paper_IDH.status) 

#1.4 Obtaining metadata
metadata<- data.frame("Barcode"= lgg.data$barcode, "IDH_status" = lgg.data$paper_IDH.status, "Gender" = lgg.data$gender, "Primary_Diagnosis" =lgg.data$primary_diagnosis)

#1.5 filtering out samples with no IDH_status
sum(is.na(metadata$IDH_status))
metadata<-metadata[!is.na(metadata$IDH_status),]
table(metadata$IDH_status)
dim(metadata)

#1.6. Division of groups
group1_WT<- metadata[(metadata$IDH_status == "WT"),]
group2_Mut<- metadata[(metadata$IDH_status == "Mutant"),]

#1.7. Bubble plot for patient demographics
colnames(metadata)
data_summary <- metadata %>%
  group_by(IDH_status, Primary_Diagnosis,Gender) %>%
  summarize(PatientCount = n())
#Plotting the demographics
ggplot(data_summary, aes(x = IDH_status, y = Primary_Diagnosis, size = PatientCount, colour = Gender)) +
  geom_point(alpha = 0.6) +
  labs(title = "Bubble Chart of Number of Patients by IDH_status, Diagnosis and Gender",
       x = "IDH_status",
       y = "Diagnosis",
       size = "Number of Patients",
       color = "Gender")
table(metadata$Primary_Diagnosis[metadata$IDH_status == "Mutant"])
table(metadata$Primary_Diagnosis[metadata$IDH_status == "WT"])
table(metadata$Gender[metadata$IDH_status == "Mutant"])
table(metadata$Gender[metadata$IDH_status == "WT"])

#1.8. Select the unstranded dataset and obtaining the read counts matrix
lgg.raw.data<-assays(lgg.data) #using summarized experiments module
dim(lgg.raw.data$unstranded) # selecting unstranded refer notes for dets
selected_data <-lgg.raw.data$unstranded[,c(group1_WT$Barcode, group2_Mut$Barcode)]
dim(selected_data)

#1.9. Data normalization and filtering this is for expression analysis
normData<- TCGAanalyze_Normalization(tabDF = selected_data, geneInfo = geneInfoHT, method= "geneLength")
# Filtering
filtData<- TCGAanalyze_Filtering(tabDF = normData,
                                 method = "quantile",
                                 qnt.cut = 0.25) # the method used is quantile normalization with cutoff of 0.25 (1st quantile)
dim(filtData)

```

```{r}
#---------------------------------------------------------Diferential Gene Expression------------------------------------------------

#Perform DEA using TCGAanalyze between the IDH Mutant and W/T groups
selectResults<-TCGAanalyze_DEA(mat1 = filtData[,c(group2_Mut$Barcode)], #control group
                               mat2 = filtData[, c(group1_WT$Barcode)], #case group
                               Cond1type = "IDH_Mutatnt",
                               Cond2type = "IDH_WT",
                               pipeline = "edgeR")
dim(selectResults)  

#Differential expression levels for the different conditions
selectResults.levels<-
  TCGAanalyze_LevelTab(selectResults, "IDH Mutant", "IDH_WT",  
                       filtData[,c(group2_Mut$Barcode)],
                       filtData[, c(group1_WT$Barcode)])
dim(selectResults.levels) # main difference in the data points for the 2 conditions

#Setting the logfc and p value filter followed in the paper logfc > 1 or <-1 and p value of <0.05
selectResults.levels$diff_exp <-"No"
selectResults.levels$diff_exp[selectResults.levels$logFC > 1 & selectResults.levels$FDR <0.05] <-"UP"
selectResults.levels$diff_exp[selectResults.levels$logFC < (-1) & selectResults.levels$FDR <0.05] <-"DOWN"
table(selectResults.levels$diff_exp)

DGEA_sig<-selectResults.levels[selectResults.levels$diff_exp == "UP"| selectResults.levels$diff_exp == "DOWN",]

#To obtaing gene names as gene symbles
converted_gene_names<- mapIds(org.Hs.eg.db, 
                       keys = selectResults.levels$mRNA, 
                       column = "SYMBOL", 
                       keytype = "ENSEMBL", 
                       multiVals = "first")
# Merge the conversion results back to your original dataframe
selectResults.levels$gene<-converted_gene_names
#assign ensemble ids to genes without gene names(lncRNA's etc.)
selectResults.levels$gene <- ifelse(is.na(selectResults.levels$gene), selectResults.levels$mRNA, selectResults.levels$gene)
sum(is.na(selectResults.levels$gene))

#All Upregulated and downregulated genes
upreg.genes<- rownames((selectResults.levels[selectResults.levels$diff_exp =='UP',]))
dnreg.genes<- rownames((selectResults.levels[selectResults.levels$diff_exp =='DOWN',]))

up_gene_symbols <- selectResults.levels$gene[selectResults.levels$diff_exp =='UP']
dn_gene_symbols <- selectResults.levels$gene[selectResults.levels$diff_exp =='DOWN']

#To compare results with the paper and check the regulation of identified TF's in paper and our analysis

#Significant transcription factors studied in the paper
paper_genes<-c("NKX2-5","FOSL1", "ETV7", "RUNX1", "RUNX3", "IRF1", "NR2F2", "PAX8", "CEBPD", "ETV4", "ELF4","NFE2L3")
p_enst<- mapIds(org.Hs.eg.db, 
                       keys = paper_genes, 
                       column = "ENSEMBL", 
                       keytype = "SYMBOL", 
                       multiVals = "first")
Sig_TF<-selectResults.levels[p_enst,]

#All transcription factors studied in the paper(Supplementary)
paper_tf<- c("FOS","ELF2","HIF1A", "CEBPA",	"ID3",	"TP63",	"JUN",	"RUNX3",	"SNAI1", "E2F1", "EGR1",	"CTNNB1",	"ATF1",	"STAT2",	"E2F7",	"STAT6",	"DDIT3",	"HOXB7",	"STAT3",	"ATF3",	"STAT5A",	"TFEC",	"NRF1",	"JUNB")
paper_tf_enst<- mapIds(org.Hs.eg.db, 
                       keys = paper_tf, 
                       column = "ENSEMBL", 
                       keytype = "SYMBOL", 
                       multiVals = "first")
all_TF_DEA<-selectResults.levels[paper_tf_enst,]
table(all_TF_DEA$diff_exp)

#Boxplot for all the significant DEG TF's
#Obtain the Read counts matrix
Sig_TF_readcounts<-as.data.frame(t(filtData[p_enst,]))
colnames(Sig_TF_readcounts)<-paper_genes
Sig_TF_readcounts$Barcode<-rownames(Sig_TF_readcounts)

#merge the dataset with the metadata for IDH_status
merged_data <- merge(Sig_TF_readcounts, metadata[,c("Barcode","IDH_status")] , by = "Barcode")
merged_data <- merged_data[, c("Barcode", "IDH_status", setdiff(names(merged_data), c("Barcode", "IDH_status")))]
merged_data$IDH_status <- as.factor(merged_data$IDH_status)
#convert it to long format to summarize the mean expression value in each group
melted_data <- merged_data %>%
  gather(key = "Gene", value = "Expression", -Barcode, -IDH_status)

# Boxplot generation
png(file= "BoxPlot_Sig_TF.png", width =1000, height =1000, res=150)
ggplot(melted_data, aes(x = IDH_status, y = Expression, fill = IDH_status)) +
  geom_boxplot() +
  facet_wrap(~ Gene, scales = "free") +
  labs(title = "Gene Expression by IDH status", x = "IDH status", y = "Gene Expression")
dev.off()
is.element(paper_tf_enst, selectResults.levels$mRNA ) #check if the genes are present in the analysis
is.element(paper_genes, up_gene_symbols) #check if the significant genes in the paper are upregulated in our analysis

#convert very p value 0 to very small number to plot -log10(FDR) in volcano plot
selectResults.levels$FDR[selectResults.levels$FDR == 0] <- 1e-10

png(file = "Volcano plot.png  ", width =1500, height = 1500, res=150)
EnhancedVolcano(selectResults.levels,
                lab = selectResults.levels$gene,  # Use gene names or IDs for labels
                selectLab = paper_genes,
                x = 'logFC',                      # Log Fold Change column
                y = 'FDR',
                cutoffLineType = 'twodash',
                cutoffLineWidth = 0.8,
                drawConnectors = TRUE,
                widthConnectors = 0.75,
                max.overlaps=20,
                title = 'Volcano plot of genes differentially expressed in IDH mutant group',
                pCutoff = 0.05,
                legendPosition = 'right',
                legendLabSize = 8,
                legendIconSize = 3.0)
dev.off()

#--------------------------------------------------Heat map Visualization-------------------------------------

#Collecting the list of top 5% up and down regulated genes into 1 file.
top5percent_up<- ceiling(0.05*NROW(selectResults.levels[selectResults.levels$diff_exp == "UP",])) # calculating the number threshold for top 5 % upregulated 
top5percent_dn<-ceiling(0.05*NROW(selectResults.levels[selectResults.levels$diff_exp == "DOWN",])) # calculating the number threshold for top 5 % downregulated genes
DGEA_top5<- rbind(head(selectResults.levels[order(selectResults.levels$logFC, decreasing =TRUE),],top5percent_up), tail(selectResults.levels[order(selectResults.levels$logFC, decreasing =TRUE),],top5percent_dn))
dim(DGEA_top5)
heat.data<-filtData[rownames(DGEA_top5),] # selecting the genes that are significantly differentiated from the filtered data
dim(heat.data)

#color based on the age groups of the samples -column colors
table(metadata$IDH_status) # get the number of samples in each category
cancer.type<-c(rep("IDH_WT", 94), rep("IDH_Mutant",419))
ccodes<-c()
for(i in cancer.type)
{
  if(i == "IDH_Mutant")
    ccodes <- c(ccodes,"red")
  else
    ccodes <- c(ccodes, "blue")
}
ccodes

#add color coding to rows
rcodes<-c()
for(i in 1:NROW(DGEA_top5))
{
  if(DGEA_top5$diff_exp[i] == "UP")
    rcodes <- c(rcodes,"green")
  else
    rcodes <- c(rcodes, "yellow")
}
rcodes

# Define custom breaks from -1 to 1 so to adjust for the skewed data.
breaks <- c(seq(-1, 0.6, length=100),  # For red
               seq(0.61, 0.8, length=100),  # For yellow
               seq(0.81, 1, length=100))
#Plotting Heat map
png(filename = "Heatmap_F.png", width = 1500, height = 1500, res =150)
par(oma = c(1,1,1,1)) #Setting outter margins
par(mar = c(1,1,1,1)) #setting inner plot margins
par(cex.main = 0.75) #size of the title
heatmap.2(as.matrix((heat.data)), #can use log values for better visualization
          col = hcl.colors(299, palette = "Red-Green"), # Diverging palette
          breaks = breaks,
          Colv = F,                         # Cluster columns
          Rowv = F,                         # Cluster rows
          dendrogram = "none",              # No cluster both rows and columns
          trace = "none",                   # Remove trace lines
          scale = "none",                    # Standardizes rows (genes) across samples
          sepcolor = "black",               #separate the columns
          key = TRUE,                       # Show color key
          cexRow = 0.5,                     # Adjust row label size
          cexCol = 0.5,                     # Adjust column label size
          margins = c(9, 7),                # Adjust margins to fit labels
          main = "Heatmap", #Title
          xlab = "Samples(n=513)",                 #X axis label
          ylab = "Genes(n=297)",                   #Y axis label   
          key.title = "Color Key",
          ColSideColors = ccodes,          # colums are the samples and are color coded based on the previous for loop.
          RowSideColors = rcodes)
legend("topright", legend = c("IDH Mutant group(n=419)", "IDH W/T group(n=94)"), fill = c("red", "blue"), title = "Column Colors", cex = 0.8)
legend("bottomleft", legend = c("Upregulated_genes(n=212)", "Downregulated genes(n=85)"), fill = c("green", "yellow"), title = "Row Colors", cex = 0.8)
dev.off()
```

```{r}
#--------------------------------Functional Enrichment anlysis using TCGAanalyze_EAcomplete
up.EA<- TCGAanalyze_EAcomplete(TFname = "Upregulated", up_gene_symbols) # produces result based on BP, CC, MF and Pathways(P)
dn.EA<- TCGAanalyze_EAcomplete(TFname = "Downregulated", dn_gene_symbols)

#Visualization
TCGAvisualize_EAbarplot(tf = rownames(up.EA$ResBP),#Rownames
                        GOBPTab = up.EA$ResBP, #results for BP
                        GOMFTab = up.EA$ResMF, #results for MF
                        GOCCTab = up.EA$ResCC, #results for CC
                        PathTab = up.EA$ResPat, #results for PAthway
                        nRGTab = up_gene_symbols, #number of genes in the list
                        nBar = 5, #max number of bars is 5 but can be increased to 10
                        text.size = 2, # 2 
                        fig.width = 30, # size of figure
                        fig.height = 15) #generates a pdf in the working directory


TCGAvisualize_EAbarplot(tf = rownames(dn.EA$ResBP),
                        GOBPTab = dn.EA$ResBP, 
                        GOMFTab = dn.EA$ResMF, 
                        GOCCTab = dn.EA$ResCC, 
                        PathTab = dn.EA$ResPat, 
                        nRGTab = dn_gene_symbols, 
                        nBar = 5, 
                        text.size = 2, 
                        fig.width = 30,
                        fig.height = 15)
```
#-------------------------------------------Machine_learning_part-----------------------------------------------------------
```{r}

# Load necessary libraries
library(dplyr)
library(tidyr)
library(caret)
library(cluster)
library(factoextra)
library(ggplot2)
library(pheatmap)
library(preprocessCore)
library(RColorBrewer)
#----------------------------------------Data_preparation_and_pre_processing------------------------------------------------
# Step 1: Data Preparation
# Simulate or load Expression data
data = Final_data 
trans = as.data.frame(t(data))

# Assign column names and remove the first row
colnames(trans) <- trans[1, ]
trans <- trans[-1, ] 

# Convert all columns to numeric
sample_ids <- rownames(trans)
gene_names <- colnames(trans)
trans <- as.data.frame(lapply(trans, function(x) as.numeric(as.character(x))))
rownames(trans) <- sample_ids
colnames(trans) <- gene_names

# Step 2: Quantile Normalization
trans <- normalize.quantiles(as.matrix(trans)) 
rownames(trans) <- sample_ids
colnames(trans) <- gene_names

# Step 3: Variance Filtering
variance <- apply(trans, 2, var, na.rm = TRUE)
threshold <- quantile(variance, 0.93, na.rm = TRUE)
filtered_data <- trans[, variance > threshold]

# Check the dimensions of the filtered data
dim(filtered_data)


#----------------------------------------PCA_Filtering_and_visaulization---------------------------------------------------
# Step 4: PCA
pca_filtered_result <- prcomp(filtered_data, scale. = TRUE)
pca_filtered_data <- as.data.frame(pca_filtered_result$x)

# Plot the PCA result 
ggplot(pca_filtered_data, aes(x = PC1, y = PC2)) +
  geom_point(size = 2) +
  labs(title = "PCA - Filtered Expression Data", x = "PC1", y = "PC2") +
  theme_minimal()

#---------------------------------------K-means_clustering_and_visaulization------------------------------------------------

# Step 5: K-means Clustering
k <- 2
kmeans_result <- kmeans(pca_filtered_data[, c("PC1", "PC2")], centers = k)
pca_filtered_data$cluster <- as.factor(kmeans_result$cluster)

# Plot the PCA with clusters
ggplot(pca_filtered_data, aes(x = PC1, y = PC2, color = cluster)) +
  geom_point(size = 2) +
  labs(title = "PCA with K-means Clustering (2 Clusters)", x = "PC1", y = "PC2") +
  theme_minimal() +
  scale_color_manual(values = rainbow(k)) 

#---------------------------------------Extracting_sample_IDs_from_clusters-------------------------------------------------

# Step 6: Extract Sample IDs for Clusters
pca_filtered_data$Sample_ID <- rownames(pca_filtered_data)
sample_cluster_mapping <- pca_filtered_data[, c("Sample_ID", "cluster")]
write.csv(sample_cluster_mapping, file = "sample_cluster_mapping.csv", row.names = FALSE)

# Step 7: Save Cluster Samples to Text File
cluster_samples <- split(sample_cluster_mapping$Sample_ID, sample_cluster_mapping$cluster)
file_conn <- file("cluster_samples.txt")
for (i in 1:length(cluster_samples)) {
  writeLines(paste("Cluster", i, "Sample IDs:"), file_conn)
  writeLines(cluster_samples[[i]], file_conn)
  writeLines("\n", file_conn)  # Add a new line between clusters
}
close(file_conn)

#--------------------------------------- Merging Cluster Data with Metadata_to compare IDH status---------------------------


# Step 8: Merging Cluster Data with Metadata
merged_data <- merge(sample_cluster_mapping, Metadata, by.x = "Sample_ID", by.y = "barcode", all.x = TRUE)
View(merged_data)
write.csv(merged_data, 'Cluster_IDH_status.csv')


#---------------------------------------Cluster_means_calculation_and_heatmap_plotting--------------------------------------

# Step 9: Calculate Cluster-Specific Means
cluster_means <- aggregate(filtered_data, by = list(Cluster = kmeans_result$cluster), FUN = mean)

# Step 10: Heatmap Visualization CLUSTER MEANS
pheatmap(cluster_means[,-1], 
         cluster_rows = TRUE, 
         cluster_cols = TRUE, 
         main = "Heatmap of Cluster Means for Expression Data",
         fontsize_row = 8, 
         fontsize_col = 8, 
         show_rownames = FALSE, 
         show_colnames = FALSE)

#---------------------------------------Log_transformation_for_visualization_of_filtered_data-------------------------------

# Step 11: Log Transformation and Z-score Normalization
filtered_data <- as.data.frame(t(filtered_data))  # Ensure samples are rows
filtered_data_log <- log(filtered_data + 1)  # Log-transform with pseudocount
filtered_data_scaled <- t(scale(t(filtered_data_log)))  # Z-score normalization


# Step 12: Define Colors and Plot Heatmap
color_palette <- colorRampPalette(c("blue", "white", "red"))(299)  # Define color palette

# Save the heatmap as PNG
png(filename = "Gene_Expression_Heatmap_logtransformed.png", width = 1800, height = 2400, res = 200)
pheatmap(filtered_data_scaled,  
         col = color_palette,  
         breaks = seq(-3, 3, length.out = 300),  
         cluster_rows = TRUE,  
         cluster_cols = FALSE,  
         fontsize_row = 4,  
         fontsize_col = 4,  
         show_rownames = FALSE,  
         show_colnames = FALSE,  
         main = "Gene Expression Heatmap of filtered data 2417 genes and 513 samples",
         xlab = "Samples",  
         ylab = "Genes",  
         key.title = "Z-score Expression")  
dev.off()  # Close the device to save the image

```
