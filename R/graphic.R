#' @name dtMotifMatch
#' @title Compute the augmented matching subsequence on SNP and reference alleles.
#' @description Calculate the best matching augmented subsequences on both SNP and reference alleles for motifs. Obtain extra unmatching position on the best matching augmented subsequence of the reference and SNP alleles.
#' @param snp.tbl A data.table with the following information:
#' \tabular{cc}{
#' snpid \tab SNP id.\cr
#' ref_seq \tab Reference allele nucleobase sequence.\cr
#' snp_seq \tab SNP allele nucleobase sequence.\cr
#' ref_seq_rev \tab Reference allele nucleobase sequence on the reverse strand.\cr
#' snp_seq_rev \tab SNP allele nucleobase sequence on the reverse strand.\cr}
#' @param motif.scores A data.table with the following information:
#' \tabular{cc}{
#' motif \tab Name of the motif.\cr
#' motif_len \tab Length of the motif.\cr
#' ref_start, ref_end, ref_strand \tab Location of the best matching subsequence on the reference allele.\cr
#' snp_start, snp_end, snp_strand \tab Location of the best matching subsequence on the SNP allele.\cr
#' log_lik_ref \tab Log-likelihood score for the reference allele.\cr
#' log_lik_snp \tab Log-likelihood score for the SNP allele.\cr
#' log_lik_ratio \tab The log-likelihood ratio.\cr
#' log_enhance_odds \tab Difference in log-likelihood ratio between SNP allele and reference allele based on the best matching subsequence on the reference allele.\cr
#' log_reduce_odds \tab Difference in log-likelihood ratio between reference allele and SNP allele based on the best matching subsequence on the SNP allele.\cr
#' }
#' @param snpids A subset of snpids to compute the subsequences. Default: NULL, when all snps are computed.
#' @param motifs A subset of motifs to compute the subsequences. Default: NULL, when all motifs are computed.
#' @param ncores The number of cores used for parallel computing. Default: 10
#' @return A data.table containing all columns from the function, 'MatchSubsequence'. Refer 'MatchSubsequence' for more details. In addition, the following columns are added:
#' \tabular{ll}{
#' snp_ref_start, snp_ref_end, snp_ref_length \tab Location and Length of the best matching augmented subsequence on both the reference and SNP allele.\cr
#' ref_aug_match_seq \tab Best matching augmented subsequence on the reference allele.\cr 
#' snp_aug_match_seq \tab Best matching augmented subsequence on the SNP allele.\cr 
#' ref_location \tab SNP location of the best matching augmented subsequence on the reference allele. Starting from zero. \cr
#' snp_location \tab SNP location of the best matching augmented subsequence on the SNP allele. Starting from zero. \cr
#' ref_extra_pwm_left \tab Left extra unmatching position on the best matching augmented subsequence of the reference allele. \cr
#' ref_extra_pwm_right \tab Right extra unmatching position on the best matching augmented subsequence of the reference allele. \cr
#' snp_extra_pwm_left \tab Left extra unmatching position on the best matching augmented subsequence of the SNP allele. \cr
#' snp_extra_pwm_right \tab Right extra unmatching position on the best matching augmented subsequence of the SNP allele. \cr
#' }
#' @author Sunyoung Shin\email{shin@@stat.wisc.edu}
#' @examples
#' data(example)
#' dtMotifMatch(motif_scores$snp.tbl, motif_scores$motif.scores, motif_scores$snp.tbl$snpid[1:100], motif_scores$motif.scores$motif[1])
#' @import data.table doMC
#' @export
dtMotifMatch<-function(snp.tbl, motif.scores, snpids=NULL, motifs=NULL, ncores=10) {
  if (all(any(class(snpids) != "character",  length(snpids)==0), is.null(snpids)==FALSE)) {
    stop("snpids must be a vector of class character or NULL.")
  } else if (all(any(class(motifs) != "character",  length(motifs)==0), is.null(motifs)==FALSE)) {
    stop("motifs must be a vector of class character or NULL.")
  }
  ncores.v2 <- min(ncores, length(snpids) * length(motifs))
  sequence.half.window.size <- (nchar(snp.tbl[1, ref_seq]) - 1) / 2
  motif.match.dt <- MatchSubsequence(snp.tbl = snp.tbl, motif.scores = motif.scores, snpids = snpids, motifs = motifs, ncores = ncores.v2)

  ##Augmentation of SNP and reference sequences###
  motif.match.dt[, len_seq := nchar(ref_seq)]
  motif.match.dt[,snp_ref_start := apply(cbind(ref_start, snp_start), 1, min)]
  motif.match.dt[,snp_ref_end := apply(cbind(ref_end, snp_end), 1, max)]
  motif.match.dt[,snp_ref_length := snp_ref_end - snp_ref_start + 1]
  
  motif.match.dt[, ref_aug_match_seq := substr(ref_seq, snp_ref_start, snp_ref_end)]
  motif.match.dt[ref_strand == "-", ref_aug_match_seq := .find_complement(ref_aug_match_seq)]
  motif.match.dt[, snp_aug_match_seq := substr(snp_seq, snp_ref_start, snp_ref_end)]
  motif.match.dt[snp_strand == "-", snp_aug_match_seq := .find_complement(snp_aug_match_seq)]
  
  ##The starting position of the motif in the augmented sequences
  motif.match.dt[ref_strand == "+", ref_location := (len_seq-1)/2 + 1 - snp_ref_start]
  motif.match.dt[ref_strand == "-", ref_location := snp_ref_end - (len_seq - 1) / 2 - 1]
  motif.match.dt[snp_strand == "+", snp_location := (len_seq - 1) / 2 + 1 - snp_ref_start]
  motif.match.dt[snp_strand == "-", snp_location := snp_ref_end - (len_seq - 1) / 2 - 1]
  motif.match.dt[, len_seq := NULL]
  
  ##PWM Location Adjustment Value for reference and SNP
  motif.match.dt[ref_strand == "+", ref_extra_pwm_left := ref_start-snp_ref_start]
  motif.match.dt[ref_strand == "-", ref_extra_pwm_left := snp_ref_end-ref_end]
  motif.match.dt[ref_strand == "+", ref_extra_pwm_right := snp_ref_end-ref_end]
  motif.match.dt[ref_strand == "-", ref_extra_pwm_right := ref_start-snp_ref_start]
  motif.match.dt[snp_strand == "+", snp_extra_pwm_left := snp_start-snp_ref_start]
  motif.match.dt[snp_strand == "-", snp_extra_pwm_left := snp_ref_end-snp_end]
  motif.match.dt[snp_strand == "+", snp_extra_pwm_right := snp_ref_end-snp_end]
  motif.match.dt[snp_strand == "-", snp_extra_pwm_right := snp_start-snp_ref_start]
   motif.match.dt
}

#' @name plotMotifMatch
#' @title Plot sequence logos of the position weight matrix of the motif and sequences of its corresponding best matching augmented subsequence on the reference and SNP allele.
#' @description Plot the best matching augmented subsequences on the reference and SNP alleles. Plot sequence logos of the position weight matrix of the motif to the corresponding positions of the best matching subsequences on the references and SNP alleles.
#' @param snp.tbl A data.table with the following information:
#' \tabular{cc}{
#' snpid \tab SNP id.\cr
#' ref_seq \tab Reference allele nucleobase sequence.\cr
#' snp_seq \tab SNP allele nucleobase sequence.\cr
#' ref_seq_rev \tab Reference allele nucleobase sequence on the reverse strand.\cr
#' snp_seq_rev \tab SNP allele nucleobase sequence on the reverse strand.\cr}
#' @param motif.scores A data.table with the following information:
#' \tabular{cc}{
#' motif \tab Name of the motif.\cr
#' motif_len \tab Length of the motif.\cr
#' ref_start, ref_end, ref_strand \tab Location of the best matching subsequence on the reference allele.\cr
#' snp_start, snp_end, snp_strand \tab Location of the best matching subsequence on the SNP allele.\cr
#' log_lik_ref \tab Log-likelihood score for the reference allele.\cr
#' log_lik_snp \tab Log-likelihood score for the SNP allele.\cr
#' log_lik_ratio \tab The log-likelihood ratio.\cr
#' log_enhance_odds \tab Difference in log-likelihood ratio between SNP allele and reference allele based on the best matching subsequence on the reference allele.\cr
#' log_reduce_odds \tab Difference in log-likelihood ratio between reference allele and SNP allele based on the best matching subsequence on the SNP allele.\cr
#' }
#' @param snpid A snpid to plot the sequences on the reference and SNP alleles
#' @param motif A motif to match the sequences with its position weight matrix
#' @param motif.lib A list of position weight matrices
#' @return Sequence logo stacks: Reference subsequences, sequence logo of reference allele matching potision weight matrix, SNP subsequences, sequence logo of SNP allele matching potision weight matrix
#' @author Sunyoung Shin\email{shin@@stat.wisc.edu}
#' @examples
#' data(example)
#' plotMotifMatch(motif_scores$snp.tbl, motif_scores$motif.scores, motif_scores$snp.tbl$snpid[86], motif_scores$motif.scores$motif[1])
#' @import data.table motifStack doMC
#' @export
plotMotifMatch<-function(snp.tbl, motif.scores, snpid, motif, motif.lib=motif_library) {
  if (class(snpid) != "character" | length(snpid)!=1) {
    stop("snpid must be a character")
  }
  if (class(motif) != "character" | length(motif)!=1) {
    stop("motif must be a character")
  }
  if(sum(! motif %in% names(motif.lib$matrix)) > 0) {
    stop("Error: The motif is not included in 'motif.lib'.")
  }
  motif.match.dt <- dtMotifMatch(snp.tbl, motif.scores, snpid, motif, ncores = 1)  
  ##snpid, motif, ref_strand, ref_seq, pwm_ref, snp_strand, snp_seq, pwm_snp, ref_location, snp_location, snp_ref_length) {
  
  ##Convert ACGT to 1234
  codes <- seq(4)
  names(codes) <- c("A", "C", "G", "T")
  ref_aug_match_seq_code <- codes[strsplit(motif.match.dt[,ref_aug_match_seq], "")[[1]]]
  snp_aug_match_seq_code <- codes[strsplit(motif.match.dt[,snp_aug_match_seq], "")[[1]]]
  
  ##Convert 1234 to (1000)(0100)(0010)(0001)
  codes.vec <- diag(4)
  rownames(codes.vec) <- c("A", "C", "G", "T")
  ref_aug_match_pwm <- mapply(function(i) codes.vec[,i], as.list(ref_aug_match_seq_code))
  snp_aug_match_pwm <- mapply(function(i) codes.vec[,i], as.list(snp_aug_match_seq_code))
  
  ##(3,2) to Augmented PWM: ___PWM__
  ref_aug_pwm <- cbind(matrix(0, 4, motif.match.dt[, ref_extra_pwm_left]), t(get(motif.match.dt[, motif], motif.lib$matrix)), matrix(0, 4, motif.match.dt[, ref_extra_pwm_right]))
  rownames(ref_aug_pwm) <- c("A", "C", "G", "T")
  snp_aug_pwm <- cbind(matrix(0, 4, motif.match.dt[, snp_extra_pwm_left]), t(get(motif.match.dt[, motif], motif.lib$matrix)), matrix(0, 4, motif.match.dt[, snp_extra_pwm_right]))
  rownames(snp_aug_pwm) <- c("A", "C", "G", "T")

  snp_loc <- motif.match.dt$ref_location
  revert.columns <- function(mat) {
    mat[, rev(seq(ncol(mat)))]
  }
  if(motif.match.dt$ref_strand == "-") {
    ref_aug_match_pwm <- revert.columns(ref_aug_match_pwm)
    ref_aug_pwm <- revert.columns(ref_aug_pwm)
    snp_loc <- ncol(ref_aug_match_pwm) - 1 - snp_loc
  }
  if(motif.match.dt$snp_strand == "-") {
    snp_aug_match_pwm <- revert.columns(snp_aug_match_pwm)
    snp_aug_pwm <- revert.columns(snp_aug_pwm)
  }
  
  par(mfrow=c(4,1), mar = c(3.5, 3.5, 1.5, 0.5))
  plotMotifLogo(pcm2pfm(ref_aug_match_pwm), paste("Reference: ", motif.match.dt[,snpid], " (", motif.match.dt[,ref_strand], ")", sep=""))
  segments(motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 0, motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 1, col="blue", lty=3, lwd=2)
  segments(motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 1, (motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 1, col="blue", lty=3, lwd=2)
  segments((motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 0, (motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 1, col="blue", lty=3, lwd=2)
  segments(motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 0, (motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 0, col="blue", lty=3, lwd=2)
  plotMotifLogo(pcm2pfm(ref_aug_pwm), motif.match.dt[,motif])
  plotMotifLogo(pcm2pfm(snp_aug_match_pwm), paste("SNP: ", motif.match.dt[,snpid], " (", motif.match.dt[,snp_strand], ") ", sep=""))
  segments(motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 0, motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 1, col="blue", lty=3, lwd=2)
  segments(motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 1, (motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 1, col="blue", lty=3, lwd=2)
  segments((motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 0, (motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 1, col="blue", lty=3, lwd=2)
  segments(motif.match.dt[,snp_loc]/motif.match.dt[,snp_ref_length], 0, (motif.match.dt[,snp_loc]+1)/motif.match.dt[,snp_ref_length], 0, col="blue", lty=3, lwd=2)
  plotMotifLogo(pcm2pfm(snp_aug_pwm), motif.match.dt[,motif])
}

.find_complement <- function(sequence) {
  if(length(sequence) > 0) {
    codes <- seq(4)
    names(codes) <- c("A", "C", "G", "T")
    return(paste(names(codes)[5 - rev(codes[strsplit(sequence, split = "")[[1]]])], collapse = ""))
  }
}