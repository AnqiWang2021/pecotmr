% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/univariate_rss_diagnostics.R
\name{extract_cs_info}
\alias{extract_cs_info}
\title{Process Credible Sets (CS) from Finemapping Results}
\usage{
extract_cs_info(con_data, cs_names, top_loci_table)
}
\arguments{
\item{con_data}{List. The method layer data from a finemapping RDS file that is not empty.}

\item{cs_names}{Character vector. Names of the Credible Sets, usually in the format "L_<number>".}

\item{top_loci_table}{Data frame. The $top_loci layer data from the finemapping results.}
}
\value{
A data frame with one row per CS, containing the following columns:
  \item{cs_name}{Name of the Credible Set}
  \item{variants_per_cs}{Number of variants in the CS}
  \item{top_variant}{ID of the variant with the highest PIP in the CS}
  \item{top_variant_index}{Global index of the top variant}
  \item{top_pip}{Highest Posterior Inclusion Probability (PIP) in the CS}
  \item{top_z}{Z-score of the top variant}
  \item{p_value}{P-value calculated from the top Z-score}
  \item{cs_corr}{Pairwise correlations of other CSs in this RDS with the CS of 
    the current row, delimited by '|', if there is more than one CS in this RDS file}
}
\description{
This function extracts and processes information for each Credible Set (CS) 
from finemapping results, typically obtained from a finemapping RDS file.
}
\details{
This function is designed to be used only when there is at least one Credible Set 
in the finemapping results usually for a given study and block. It processes each CS, 
extracting key information such as the top variant, its statistics, and 
correlation information between multiple CS if available.
}
