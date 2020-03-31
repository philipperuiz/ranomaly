#' ASVenn
#'
#'
#' @param dada_res Results of dada2_fun()
#' @param output Output directory
#' @param rank Taxonomic rank name, or 'ASV' for ASV level.
#' @param column1 Factor to test.
#' @param subset Subset sample, please provide as c(FACTOR,LEVEL).
#' @param lvls Vector list levels of factor to print in venn diagram (max. 5).
#' @param krona Krona of exclusive ASV or shared with informed level and others. Must be among levels of column1 argument.
#' @param shared shared [TRUE] or exclusive [FALSE] mode.
#'
#'
#' @return Export a venn diagram with corresponding tabulated file.
#'
#' @importFrom glue glue
#' @export



ASVenn_fun <- function(data = data, output = "./ASVenn/", rank = "ASV",
                            column1 = NULL, subset = "", lvls = "", krona = "",
                            shared = TRUE){

  invisible(flog.threshold(futile.logger::ERROR, name = "VennDiagramLogger"))

  if(!dir.exists(output)){
    dir.create(output, recursive=TRUE)
  }


  #Check phyloseq object named data
  if(!any(ls()=="data")){
    for(i in ls()){
      fun <- paste("cLS <- class(",i,")")
      eval(parse(text=fun))
      # print(c(i,cLS))
      if(cLS == "phyloseq"){
        fun <- paste("data = ", i)
        eval(parse(text=fun))
      }
    }
  }


  if (is.null(column1)){
    print_help(opt_parser)
    flog.info("You must provide a factor:")
    print(names(sample_data(data)))
    quit()
  }

  #Subset data
  if(subset!=""){
    flog.info('Subset phyloseq object ...')
    args1 <- unlist(strsplit(subset,","))
    fun <- paste("data <- subset_samples(data, ",args1[1]," %in% '",args1[2],"')",sep="")
    eval(parse(text=fun))
    TITRE=paste(column1, args1[1], args1[2], sep="-")
  }else{
    TITRE=paste(column1)
  }


  #Nombre d'espèce par matrice
  flog.info('Parsing factor ...')
  level1 <- na.omit(levels(as.factor(sample_data(data)[,column1]@.Data[[1]])) )
  TFdata <- list()
  TFtax <- list()
  if(!is.null(refseq(data, errorIfNULL=FALSE))){
    refseq1 <- as.data.frame(refseq(data)); names(refseq1)="seq"
  }else{flog.info('No Tree ...')}
  databak <- data
  for(i in 1:length(level1)){
    databak -> data
    LOC=as.character(level1[i])
    print(LOC)
    fun <- paste("data <- subset_samples(data, ",column1," %in% '",LOC,"')",sep="")
    eval(parse(text=fun))
    if(rank=="ASV"){
      print("ASV")
      sp_data = data
      sp_data <- prune_taxa(taxa_sums(sp_data) > 0, sp_data)
    }else{
      print(rank)
      sp_data <- tax_glom(data, rank)
      sp_data <- prune_taxa(taxa_sums(sp_data) > 0, sp_data)
      cat(LOC,ntaxa(sp_data)," ", rank, " \n")
    }

    ttable <- sp_data@tax_table@.Data
    otable <- as.data.frame(otu_table(sp_data))
    # print(nrow(ttable))

    if(!any(rownames(ttable) == rownames(otable))){flog.info("Different order in otu table and tax table");quit()}

    TT = cbind(otable,ttable)
    TFdata[[i]] <- TT
    TFtax[[i]] <- cbind(row.names(TT), as.character(apply(TT[,colnames(ttable)], 1, paste, collapse=";") ) ) #c("Kingdom","Phylum","Class","Order","Family","Genus","Species")
    row.names(TFtax[[i]]) = TFtax[[i]][,1]
    # write.table(TT, paste(output,"/otu_table_sp_",LOC,".csv",sep=""), sep="\t", quote=FALSE, col.names=NA)

  }


  ## Venn diag
  flog.info('Defining unique taxa ...')
  alltax <- do.call(rbind, TFtax)
  alltax <- alltax[!duplicated(alltax[,1]),]
  row.names(alltax)=alltax[,1]


  flog.info('Plotting ...')
  VENNFUN <- function(mode = 1){
    if(mode==1){
      venn.plot <- venn.diagram(TF, filename = NULL, col = "black",
                                fill = rainbow(length(TF)), alpha = 0.50,
                                cex = 1.5, cat.col = 1, lty = "blank",
                                cat.cex = 1.8, cat.fontface = "bold",
                                margin = 0.1, main=TITRE, main.cex=2.5,
                                fontfamily ="Arial",main.fontfamily="Arial",cat.fontfamily="Arial") #cat.dist = 0.09,
      png(paste(output,'/',TITRE,'_venndiag.png',sep=''), width=20, height=20, units="cm", res=200)
      grid.draw(venn.plot)
      invisible(dev.off())

      ov <- calculate.overlap(TF)
      print(sapply(ov, length))

      flog.info('Calculating lists ...')
      uniqTax = TABf = unique(do.call(c,TF))
      for (j in 1:length(TF)){
        TABtest = TF[[j]]
        TABtest_filt=rep(0, length(uniqTax))
        for (i in 1:length(uniqTax)) {
          featureI = uniqTax[i]
          res=grep( paste('^',featureI,'$', sep="" ) , TABtest)
          if(length(res)>0){TABtest_filt[i]=length(res)
          }
        }
        TABf=cbind.data.frame( TABtest_filt, TABf )
        names(TABf)[1] = names(TF)[j]
      }
      if(exists("refseq1")){
        TABf <- cbind(TABf,alltax[as.character(TABf$TABf),2], refseq1[as.character(TABf$TABf),])
        names(TABf) <- c(rev(names(TF)), "ASV", "taxonomy", "seq")
      }else{
        TABf <- cbind(TABf,alltax[as.character(TABf$TABf),2])
        names(TABf) <- c(rev(names(TF)), "ASV", "taxonomy")
      }

      write.table(TABf, paste(output,"/",TITRE,"_venn_table.csv",sep=""), sep="\t", quote=FALSE, row.names=FALSE)
    } else if(mode == 2){
      png(paste(output,'/',TITRE,'_venndiag.png',sep=''), width=20, height=20, units="cm", res=200)
      venn.plot <- venn::venn(TF , zcol=rainbow(length(TF)))
      #venn::venn(TF[c("LI","LA","EA","FI","TR","AI")] , zcol=rainbow(length(TF[c("LI","LA","EA","FI","TR","AI")])))
      #venn::venn(TF[c("FI", "TR")] , zcol=rainbow(length(TF[c("FI", "TR")])))
      dev.off()
      ENVS = names(TF)
      Tabf <- NULL; Tab1 <- NULL
      for(i in ENVS){
        tt = c(i, ENVS[ENVS != i])
        print(tt)
        yy = Reduce(setdiff, TF[tt])
        print(length(yy))
        Tab1 <- cbind(rep(i, length(yy)), alltax[yy,])
        Tabf <- rbind(Tabf, Tab1)
      }
      yy <- Reduce(intersect, TF)
      Core <- cbind(rep("core", length(yy)), alltax[yy,])
      Tabf <- rbind(Core, Tabf)
      write.table(Tabf, paste(output,"/",TITRE,"_venn_table.csv",sep=""), sep="\t", quote=FALSE, row.names=FALSE)
    }
  }

  # Specific use to screen taxonomic composition of shared taxa...
  if(krona != ""){
    TF <- TFbak
    flog.info('Krona ...')
    env1 <- TF[[krona]]
    others1 <- unique( unlist( TF[level1[level1!=krona]] ) )

    TF2 <- list(env1, others1)
    names(TF2) <- c(krona, "others")
    #Venn 2
    venn.plot <- venn.diagram(TF2, filename = NULL, col = "black",
                              fill = rainbow(length(TF2)), alpha = 0.50,
                              cex = 1.5, cat.col = 1, lty = "blank",
                              cat.cex = 1.8, cat.fontface = "bold",
                              margin = 0.1, main=TITRE, main.cex=2.5,
                              fontfamily ="Arial",main.fontfamily="Arial",cat.fontfamily="Arial") #cat.dist = 0.09,
    venn_tab=paste(output,"/",TITRE,"_",krona, "_kronaVenn.png", sep="")
    png(venn_tab, width=20, height=20, units="cm", res=200)
    grid.draw(venn.plot)
    invisible(dev.off())

    #Krona
    if(shared==TRUE){
      L1 = intersect(env1, others1)
    }else{
      L1 = setdiff(env1, others1)
    }

    subtaxdata=prune_taxa(L1,data)
    ttable <- as.data.frame(subtaxdata@tax_table@.Data)
    fttable = cbind.data.frame(rep(1,nrow(ttable)),ttable)
    fttable$ASV = row.names(fttable)
    dir.create("00test")
    flog.info('Write Krona table ...')
    krona_tab=paste(output,"/",TITRE,"_",krona, "_krona.txt", sep="")
    write.table(fttable, krona_tab, col.names=FALSE, row.names=FALSE, quote=FALSE, sep="\t")

    flog.info('Generate Krona html ...')
    output <- paste(output,"/",TITRE,"_",krona, "_krona.html", sep = "")
    system(paste("ktImportText", krona_tab, "-o", output, sep = " "))
    # browseURL(output)
  }



  TFbak <- TF <- sapply(TFtax, row.names)
  names(TFbak) = names(TF) = level1

  if(length(level1)>5){
    flog.info('Too much levels (max. 5) ...')
    if(lvls == ""){
      flog.info('Selecting 5 first levels ...')
      # TF <- TF[c(1:5)]
      VENNFUN(mode=2)
    }else{
      flog.info(glue('Selecting {lvls} ...'))
      LVLs <- unlist(strsplit(lvls,","))
      TF <- TF[LVLs]
    }
  } else {
    VENNFUN()
  }

  flog.info('Done ...')

}