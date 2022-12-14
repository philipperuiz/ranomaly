#' Metacoder Differential Analysis function.
#'
#' Plot heattrees function
#'
#' @param psobj A phyloseq object.
#' @param min Minimum read number.
#' @param col Column name of factor to test (among sample_variables(data))
#' @param rank Taxonomy rank to merge features that have same taxonomy at a certain taxonomic rank (among rank_names(data), or 'ASV' for no glom)
#' @param title Title for figures output.
#' @param plot1 Plot heattrees or not
#' @param signif Plot only siignificant or not
#'
#' @importFrom metacoder calc_obs_props filter_obs


launch_metacoder <- function(psobj, min, col, rank, title = "", plot1 = TRUE, signif = TRUE){

  vector <- unique(data.frame(sample_data(psobj)[,col])[,1])

  mean_ratio <- function(abund_1, abund_2) {
    log_ratio <- log2(mean(abund_1) / mean(abund_2))
    if (is.nan(log_ratio)) {
      log_ratio <- 0
    }
    list(log2_mean_ratio = log_ratio,
         median_diff = median(abund_1) - median(abund_2),
         mean_diff = mean(abund_1) - mean(abund_2),
         wilcox_p_value = wilcox.test(abund_1, abund_2)$p.value)
  }

  flog.info('Transform sample counts...')

  if(rank != '' & rank != 'ASV'){
    psobj <- tax_glom(psobj, taxrank=rank)
  }
  flog.info('Zeroing low counts...')
  obj <- parse_phyloseq(psobj, class_regex = "(.*)", class_key = "taxon_name")
  obj$data$otu_table <- zero_low_counts(obj, "otu_table", min_count = min, use_total = TRUE)
  no_reads <- rowSums(obj$data$otu_table[, obj$data$sample_data$sample_id]) == 0
  obj <- filter_obs(obj, "otu_table", ! no_reads, drop_taxa = TRUE)
  if(nrow(obj$data$otu_table)==0){return(NULL)}

  # Normalization
  obj$data$otu_table <- calc_obs_props(obj, "otu_table")

  flog.info('Calculating taxon abundance...')
  obj$data$tax_abund <- calc_taxon_abund(obj, "otu_table",  cols = obj$data$sample_data$sample_id)
  obj$data$tax_abund$total <- rowSums(obj$data$tax_abund[, -1]) # -1 = taxon_id column
  obj$data$n_samples <- calc_n_samples(obj,data="tax_abund")

  flog.info('Comparing groups...')
  fun <- paste('obj$data$diff_table <- compare_groups(obj, data = "tax_abund", cols = obj$data$sample_data$sample_id, groups = obj$data$sample_data$', col, ',func = mean_ratio)', sep='')
  eval(parse(text=fun))

  # obj$data$diff_table$log2_median_ratio[is.infinite(obj$data$diff_table$log2_median_ratio)] <- 0
  table <- merge(obj$data$diff_table, obj$data$tax_data,by='taxon_id')
  # write.table(merge(obj$data$diff_table, obj$data$tax_data,by='taxon_id'),file = paste(output,'/metacoder_',var,'_',col,'_',rank,'.csv',sep=''),sep="\t", col.names=NA)

  # Write signif table???
  # return(obj)
  # # save.image("debug.rdata")
  # # diffT <- obj$data$diff_table
  # # taxT <- obj$data$tax_data
  # #
  # # tt=na.omit(diffT[diffT$wilcox_p_value <=0.05,])
  # # na.omit(taxT[diffT$wilcox_p_value <=0.05,])
  # write.table(merge(obj$data$diff_table[obj$data$diff_table$wilcox_p_value<0.05,], obj$data$tax_data[obj$data$diff_table$wilcox_p_value<0.05,],by='taxon_id'),file = paste(output,'/metacoder_signif_',var,'_',col,'_',rank,'.csv',sep=''),sep="\t", col.names=NA)
  if(plot1 == TRUE){
    flog.info('Plotting all...')
    col_range <-  c("cyan", "gray", "tan")


    if(length(vector) == 2){
      fun <- paste0('p1 <- heat_tree(obj,
    node_label = taxon_names,
    node_size = total,
    node_color = log2_mean_ratio,
    node_color_interval = c(-3,3),
    edge_color_interval = c(-3, 3),
    node_color_range = diverging_palette(),
    node_color_trans = "linear",
    node_size_axis_label = "Size: Number reads",
    node_color_axis_label = "Color: Log2mean brown ',vector[1],', green: ',vector[2],'",
    layout = "davidson-harel",
    initial_layout = "reingold-tilford",
    repel_labels = TRUE,
    repel_force = 3,
    overlap_avoidance = 3,
    node_label_size_range=c(0.02,0.045),
    make_edge_legend=FALSE) + ggtitle("',title,'") + theme(plot.title = element_text(size = 16, face = "bold"))', sep ='')
    }

    if(length(vector) > 2){
      fun <- paste0('p1 <- heat_tree_matrix(obj,
      data="diff_table",
      node_label = taxon_names,
      node_size = total,
      node_color = log2_mean_ratio,
      node_color_interval = c(-3,3),
      edge_color_interval = c(-3, 3),
      node_color_range = diverging_palette(),
      node_color_trans = "linear",
      node_size_axis_label = "Size: Number of reads",
      node_color_axis_label = "Color: Log 2 ratio of mean proportions",
      layout = "davidson-harel",
      initial_layout = "reingold-tilford",
      repel_labels = TRUE,
      repel_force = 3,
      overlap_avoidance = 3,
      make_edge_legend=FALSE,
      node_label_size_range=c(0.01,0.04),
      row_label_size=16,
      col_label_size=16,
      tree_label_size = 12) + ggtitle("',title,'") + theme(plot.title = element_text(size = 16, face = "bold"))', sep ='')
    }
    eval(parse(text=fun))
    flog.info('Done.')

    if( signif==TRUE){
      obj$data$diff_table$log2_mean_ratio[obj$data$diff_table$wilcox_p_value > 0.05 | is.na(obj$data$diff_table$wilcox_p_value)] <- 0

      list_taxon <- taxon_names(obj)
      signif_taxon <- obj$data$diff_table$taxon_id[obj$data$diff_table$wilcox_p_value < 0.05 & !is.na(obj$data$diff_table$wilcox_p_value)]
      list_taxon[setdiff(names(list_taxon),signif_taxon)] <- NA


      flog.info('Plotting only significant...')
      if(length(vector) == 2){
        fun <- paste0('p2 <- heat_tree(obj,
          node_label = list_taxon,
          node_size = total,
          node_color = log2_mean_ratio,
          node_color_interval = c(-3,3),
          edge_color_interval = c(-3, 3),
          node_color_range = diverging_palette(),
          node_color_trans = "linear",
          node_size_axis_label = "Size: Number of reads",
          node_color_axis_label = "Color: Log2mean brown ',vector[1],', green: ',vector[2],'",
          layout = "davidson-harel",
          initial_layout = "reingold-tilford",
          make_edge_legend=FALSE,
          overlap_avoidance = 3,
          repel_labels = TRUE,
          repel_force = 3,
          node_label_size_range=c(0.025,0.045)) + ggtitle("',title,' (Only significants)") + theme(plot.title = element_text(size = 16, face = "bold"))', sep ='')
      }
      if(length(vector) > 2){
        fun <- paste0('p2 <- heat_tree_matrix(obj,
            data="diff_table",
            node_label = list_taxon,
            node_size = total,
            node_color = log2_mean_ratio,
            node_color_interval = c(-3,3),
            edge_color_interval = c(-3, 3),
            node_color_range = diverging_palette(),
            node_color_trans = "linear",
            node_size_axis_label = "Size: Number of reads",
            node_color_axis_label = "Color: Log 2 ratio of mean proportions",
            layout = "davidson-harel",
            initial_layout = "reingold-tilford",
            repel_labels = TRUE,
            repel_force = 3,
            overlap_avoidance = 3,
            make_edge_legend=TRUE,
            node_label_size_range=c(0.03,0.04),
            row_label_size=16,
            col_label_size=16,
            tree_label_size = 12) + ggtitle("',title,' (Only significants)") + theme(plot.title = element_text(size = 16, face = "bold"))', sep ='')
      }
      eval(parse(text=fun))
      flog.info('Done.')
      graphics.off()

      # p <- list(p1,p2)
      p <- list(p1,p2,table)
      return (p)
    } else {
      return(p1)
    }

  } else {
    p1=NULL;p2=NULL
    p <- list(p1,p2,table)
    return(p)
  }


}




#' Metacoder Differential Analysis wrapper.
#'
#' @param data a phyloseq object (output from decontam or generate_phyloseq)
#' @param output Output directory
#' @param rank Taxonomy rank to merge features that have same taxonomy at a certain taxonomic rank (among rank_names(data), or 'ASV' for no glom)
#' @param column1 Column name of factor to test (among sample_variables(data))
#' @param signif Plot only significant.
#' @param plottrees Plot heattrees (long treatments).
#' @param min Minimum number of reads for a taxa to be represented.
#' @param comp Comma separated list of comparison to test. Comparisons are informed with a tilde (A~C,A~B,B~C). If empty, test all combination
#' @param save.file Boolean whether to save output as files or not.
#' @param verbose Set to 3 for debug.
#'
#' @return Returns list with table of features and heattree plots for each comparison. Exports plots and CSV file listing significant differentialy abundant ASVs.
#'
#' @import phyloseq
#' @import ggplot2
#' @importFrom metacoder zero_low_counts calc_taxon_abund calc_n_samples compare_groups parse_phyloseq heat_tree diverging_palette taxon_names
#' @importFrom gridExtra marrangeGrob
#'
#' @export


# Decontam Function

metacoder_fun <- function(data = data, output = "./metacoder", column1 = "", rank = "Species",
                          signif = TRUE, plottrees = FALSE, min ="1000", comp = "all", save.file=FALSE,
                          verbose = 1){

  if(verbose == 3){
    invisible(flog.threshold(DEBUG))
  } else {
    invisible(flog.threshold(INFO))
  }

  if(!dir.exists(output)){
    dir.create(output, recursive = TRUE)
  }


  set.seed(1)
  table <- data.frame()
  outF = list()
  if(comp == "matrix"){
    flog.info("Comparison in matrix...")
    titleFact = paste('Matrix column ',column1,' at rank ',rank,sep='')
    gg <- launch_metacoder(psobj=data, min=min, col=column1, rank=rank, title=titleFact, plot1=plottrees, signif=signif)
    outF[['matrix']]$raw <- gg[1]
    outF[['matrix']]$signif <- gg[2]
    outF$table <- gg[3]
    plots = marrangeGrob(grobs=gg[1:2],nrow=1,ncol=2)
    ggsave(paste(output,'/metacoder_',column1,'_',rank,'.png',sep=''),plot=plots, width=30, height=16, dpi = 320)
  }
  else{
    if(comp == "all"){
      flog.info(paste('Comparing all possibilities.',sep=' '))
      fun <- paste('combinaisons <- combn(na.omit(unique(sample_data(data)$',column1,')),2) ',sep='')
      eval(parse(text=fun))
    }
    else {
      flog.info(paste('Comparing ', comp, sep=' '))
      comp_list <- unlist(strsplit(comp,","))
      combinaisons <- matrix(, nrow = 2, ncol = length(comp_list))
      for (i in 1:length(comp_list)){
        tmp <- unlist(strsplit(comp_list[i],"\\~"))
        # cbind(combinaisons,tmp)
        combinaisons[1,i] <- tmp[1]
        combinaisons[2,i] <- tmp[2]
      }
    }
    p_list <- c()



    '%!in%' <- function(x,y)!('%in%'(x,y))
    for (comp in (1:ncol(combinaisons))){
      flog.info(paste('Comparison ...',combinaisons[1,comp], combinaisons[2,comp]))
      fun <- paste('tmp <- sample_data(data)$',column1,sep='')
      eval(parse(text=fun))
      if((combinaisons[1,comp] %!in% tmp) || combinaisons[2,comp] %!in% tmp){
        flog.warn(paste(combinaisons[1,comp],' not in sample_data. Next;'),sep='')
        next
      }
      fun <- paste('psobj <- subset_samples(data, ',column1,' %in% c("',combinaisons[1,comp],'","',combinaisons[2,comp],'"))',sep='')
      eval(parse(text=fun))
      titleFact = paste(combinaisons[1,comp], ' VS ', combinaisons[2,comp],sep='')
      pp <- launch_metacoder(psobj=psobj, min=min, col=column1, rank=rank, title=titleFact, plot1=plottrees, signif=signif)

      table <- rbind(table,pp[[3]])
      p_list <- c(p_list,pp[1:2])
      outF[[paste(combinaisons[,comp],collapse="_vs_")]]$raw <- pp[1]
      outF[[paste(combinaisons[,comp],collapse="_vs_")]]$signif <- pp[2]
      outF$table = table
      #outF[[paste(combinaisons[,comp],collapse="_vs_")]] = list(plot = marrangeGrob(grobs=pp[1:2],nrow=1,ncol=2) )

    }

    flog.info('Output...')
    write.table(table,file = paste(output,'/metacoder_signif_',rank,'.csv',sep=''),sep="\t",row.names=FALSE)

    if(plottrees == TRUE){
      plots = marrangeGrob(grobs=p_list,nrow=1,ncol=2)
      ggsave(paste(output,'/metacoder_',column1,'_',rank,'.pdf',sep=''), plots, width = 40, height = 20)
    }
  }

  graphics.off()
  # save(list = ls(all.names = TRUE), file = "debug.rdata", envir = environment())
  flog.info('Finish.')
  return(outF)

}
