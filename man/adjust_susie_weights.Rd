% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/susie_wrapper.R
\name{adjust_susie_weights}
\alias{adjust_susie_weights}
\title{Adjust SuSiE Weights}
\usage{
adjust_susie_weights(
  twas_weights_results,
  condition,
  keep_variants,
  allele_qc = TRUE
)
}
\arguments{
\item{condition}{specific condition.}

\item{keep_variants}{Vector of variant names to keep.}

\item{allele_qc}{Optional}

\item{weight_db_file}{A RDS file containing TWAS weights.}
}
\value{
A list of adjusted xQTL coefficients and remained variants ids
}
\description{
This function adjusts the SuSiE weights based on a set of intersected variants.
It subsets various components like lbf_matrix, mu, and scale factors based on these variants.
}
