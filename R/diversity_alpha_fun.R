#' alpha diversité graphique
#' @param data a phyloseq object (output from decontam or generate_phyloseq)
#' @param col1 Metadata column name (from sample_variables(data)).
#' @param col2 Metadata column name (from sample_variables(data)).
#' @param measures Indices among "Observed","Shannon","Simpson","InvSimpson"
#'
#' @return A plot.
#'

alphaPlot <- function(data = data, col1 = "", col2 = "", measures = c("Shannon")) {
  flog.info('Plotting ...')
  if(col2 == ''){
    p <- plot_richness(data,x=col1, color=col1, measures=measures)
  } else{
    p <- plot_richness(data,x=col1, color=col2, measures=measures)
  }
  p$layers <- p$layers[-1]
  if(col2 != ""){legpos = "right"}else{legpos = "none"}
  p <- p + ggtitle('Alpha diversity indexes') +  geom_boxplot(alpha = 1, outlier.shape = NA) +
    theme_bw() +
    theme(axis.text.x = element_text(angle = 45, hjust=1),
    legend.position = legpos, axis.text=element_text(size=15),
    axis.title=element_text(size=16,face="bold"),
    strip.text.x = element_text(size = 18,face="bold"),
    title=element_text(size=16,face="bold"))
  flog.info('Done.')
  return(p)
}


alphaPlotly <- function(data=data, alpha=alpha, col1='', col2='', measures=c("Shannon")) {
  alpha[,col1] <- sample_data(data)[gsub('\\.','-',rownames(alpha)),col1]
  alpha <- melt(alpha, id=c(col1), measure.vars = measures)
  for (el in measures){
    fun <- glue('p <- plot_ly(alpha, x=~{col1}, y=~{el}, color=~col1, type="box")')
    print(fun)
  }
}



#' Diversity Alpha
#'
#' Provides boxplots with multiples diversity indices and statistical tests like ANOVA with post hoc test and non parametric Wilcoxon tests.
#'
#' @param data a phyloseq object (output from decontam or generate_phyloseq)
#' @param output Output directory
#' @param column1 Column name of first factor to test (covariable in ANOVA), or principal factor if only one factor to test.
#' @param column2 Column name of second factor to test (last factor in ANOVA).
#' @param column3 Column name of subjects in case of repeated mesures (mixed model)
#' @param supcovs One or more supplementary covariables to test in anova (provided as comma separated vector)
#' @param measures Diversity indices (provided as comma separated vector)
#' @param verbose Boolean
#'
#' @return Return plots and tests as list and export them in the output directory.
#'
#' @import phyloseq
#' @import ggplot2
#' @importFrom nlme lme
#' @importFrom glue glue
#' @import futile.logger
#' @export


# Decontam Function

diversity_alpha_fun <- function(data = data, output = "./plot_div_alpha/", column1 = "", column2 = "",
                                column3 = "", supcovs = "", measures = c("Observed","Shannon","Simpson","InvSimpson"), verbose = TRUE){
  if(verbose){
    invisible(flog.threshold(INFO))
  } else {
    invisible(flog.threshold(ERROR))
  }


  if(!dir.exists(output)){
    dir.create(output, recursive=TRUE)
  }


  if(column1 == ""){
    flog.error('You need to provide at least one column.')
    return(1)
  }

  if(!(column1 %in% colnames(sample_data(data)))){
    flog.error(paste(column1, ' not in metadata.'))
    return(1)
  }

  ## Gestion des NA
  if(!all(is.na(sample_data(data)[,column1]))){
    fun <- paste("data <- subset_samples(data, !is.na(",column1,"))",sep="")
    eval(parse(text=fun))

    if(column2 != ''){
      fun <- paste("data <- subset_samples(data, !is.na(",column2,"))",sep="")
      eval(parse(text=fun))
    }

    if(column3 != ''){
      fun <- paste("data <- subset_samples(data, !is.na(",column3,"))",sep="")
      eval(parse(text=fun))
    }

    #alpha diversité tableau
    resAlpha = list()

    flog.info('Alpha diversity tab ...')

    p <- alphaPlot(data, column1, column2, measures)

    resAlpha$plot = p
    ggsave(paste(output,'/alpha_diversity.eps',sep=''), plot=p, height = 15, width = 30, units="cm", dpi = 500, device="eps")

    alphatable <- estimate_richness(data, measures = measures )
    anova_data <- cbind(sample_data(data), alphatable)
    anova_data$Depth <- sample_sums(data)
    resAlpha$alphatable <- anova_data
    # row.names(resAlpha$alphatable) <- gsub("X","",row.names(resAlpha$alphatable))
    write.table(resAlpha$alphatable,paste(output,'/alphaDiversity_table.csv',sep=''), sep="\t", row.names=TRUE, col.names=NA, quote=FALSE)
    flog.info('Done.')

    if(length(levels(as.factor(anova_data[,column1])))>1 & mean(table(anova_data[,column1])) != 1 ){
      flog.info('ANOVA ...')
      # variables <- paste(sep=" + ", "Depth", var1)
      # sink(paste(output,'/all_ANOVA.txt', sep=''), split = FALSE)

      for (m in measures){
        flog.info(paste("\n\n############\n",m,"\n############\n"))

        if(supcovs != ""){
          COVS <- sapply(strsplit(supcovs,","), '[')
          flog.debug(COVS)
          if(column2 != ''){
            f <- paste(m," ~ ", "Depth + ", paste(COVS, collapse="+"), "+", column1," + ",column2)
            anova_data$fact1 <- paste( anova_data[,column1],  anova_data[,column2], sep="_")
          } else {
            f <- paste(m," ~ ", "Depth + ", paste(COVS, collapse="+"), "+", column1)
          }
        } else {
          if(column2 != ''){
            f <- paste(m," ~ ", "Depth + ", column1," + ",column2)
            anova_data$fact1 <- paste( anova_data[,column1],  anova_data[,column2], sep="_")
          } else {
            f <- paste(m," ~ ", "Depth + ", column1)
          }
        }

        flog.info("############\nANOVA + pairwise wilcox test\n")
        flog.debug(paste0('Formula: ',f))
        anova_res1 <- aov( as.formula(paste(f)), anova_data)

        aov1 <- summary(anova_res1)
        # stop()
        # # post hoc test  commented du to conflict between LSD.test() and DESeq() function. #' @importFrom agricolae LSD.test
        # cat("############\npost hoc LSD.test\n")
        # if(column2 == ''){
        #   fun = glue("lsd1 <- LSD.test(anova_res1, '{column1}', p.adj='fdr')")
        #   eval(parse(text = fun))
        #   print(lsd1)
        # } else {
        #   fun = glue("lsd1 <- LSD.test(anova_res1, '{column2}', p.adj='fdr')")
        #   eval(parse(text = fun))
        #   print(lsd1)
        # }

        flog.info(paste("\n##pvalues of pairwise wilcox test on ", m, "with FDR correction \n"), sep="")
        fun <- paste("wilcox_res1 <- pairwise.wilcox.test(anova_data$",m,", anova_data[,column1], p.adjust.method='none')", sep="")
        eval(parse(text = fun))
        # print(round(wilcox_res1$p.value,3))
        wilcox_col1 <- round(wilcox_res1$p.value,3)
        fun <- glue("resAlpha[[\"{m}\"]] <- list(anova = aov1, wilcox_col1 = wilcox_col1)")
        write.table(wilcox_col1, paste(output,"/anovatable.csv", sep=""), sep="\t", col.names=NA)
        # write.table(aov1, paste(output,"/anovatable.csv", sep=""), sep="\t", col.names=NA)  # need output for aov
        # print(fun)
        eval(parse(text=fun))

        if(column2 != ''){
          flog.info(paste("\n##pvalues of pairwise wilcox test on ", m, "with FDR correction \n"), sep="")
          fun <- paste("wilcox_res1 <- pairwise.wilcox.test(anova_data$",m,", anova_data[,column2], p.adjust.method='none')", sep="")
          eval(parse(text = fun))
          wilcox_col2_fdr <- round(wilcox_res1$p.value,3)

          flog.info(paste("##pvalues of pairwise wilcox test on ", m, " with collapsed factors (no correction)\n"), sep="")
          fun <- paste("wilcox_res <- pairwise.wilcox.test(anova_data$",m,", anova_data$fact1, p.adjust.method='none')", sep="")
          eval(parse(text = fun))
          wilcox_col2_collapsed = round(wilcox_res$p.value,3)

          fun <- glue("resAlpha[[\"{m}\"]] <- c(resAlpha[[\"{m}\"]], list(wilcox_col2_fdr = wilcox_col2_fdr, wilcox_col2_collapsed = wilcox_col2_collapsed))")
          eval(parse(text=fun))
        }
        if(column3 != ''){
          cat("\n############\nANOVA repeated measures\n")
          # print(paste(f,"+ Error(",column3,")"))
          anova_res <- aov( as.formula(paste(f,"+ Error(",column3,")")), anova_data)
          res <- summary(anova_res)
          anovarepeat = res

          cat("\n############\nMixed effects models (nlme::lme)\n")
          # print(paste("lme1 = anova(lme(as.formula(",f,"), random = ~1 | ",column3,", data = anova_data, method = 'ML') )", sep=""))
          fun <- paste( "lme1 = anova(lme(as.formula(",f,"), random = ~1 | ",column3,", data = anova_data, method = 'ML') ) ", sep="")
          eval(parse(text=fun))

          mixedeffect = lme1
          fun <- glue("resAlpha[[\"{m}\"]] <- c(resAlpha[[\"{m}\"]], list(anovarepeat = anovarepeat, mixedeffect = mixedeffect))")
          eval(parse(text=fun))
        }
      }
      # sink()

    }else{flog.info('Factor with less than 2 levels, no test ...'); flog.info(levels(as.factor(anova_data[,column1])))}
    flog.info('Done.')


  }else{flog.info(paste(column1, 'is all NA.'))}

  flog.info('Finish.')
  save(resAlpha, file=paste(output,'/alpha_robjects.Rdata',sep=''))
  return(resAlpha)

}
