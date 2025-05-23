context("allele_qc")
library(data.table)

create_allele_data <- function(seed, n=100, match_min_prop=0.8, ambiguous=FALSE, non_actg=FALSE, edge_cases=FALSE) {
  set.seed(seed)
  num_pass <- n*match_min_prop
  sumstat_A1 <- sample(c("A", "T", "G", "C"), num_pass, replace = TRUE)
  sumstat_A2 <- unlist(lapply(sumstat_A1, function(x) {
    if (x == "A") {
      return(sample(c("G", "C"), 1))
    } else if (x == "T") {
      return(sample(c("G", "C"), 1))
    } else if (x == "G") {
      return(sample(c("A", "T"), 1))
    } else if (x == "C") {
      return(sample(c("A", "T"), 1))
    }
  }))

  if (ambiguous) {
    # Strand Ambiguous SNPs 
    sumstat_A1 <- c(sumstat_A1, sample(c("A", "T", "G", "C"), n-num_pass, replace = TRUE))
    sumstat_A2 <- unlist(c(sumstat_A2, lapply(sumstat_A1[(num_pass+1):length(sumstat_A1)], function(x) {
      if (x == "A") {
        return("T")
      } else if (x == "T") {
        return("A")
      } else if (x == "G") {
        return("C")
      } else if (x == "C") {
        return("G")
      }
    })))
  } else if (non_actg) {
    # Non-ATCG coding SNPs
    sumstat_A1 <- c(sumstat_A1, sample(c("ATG", "TAC", "GACA", "CTAA"), n-num_pass, replace = TRUE))
    sumstat_A2 <- unlist(c(sumstat_A2, lapply(sumstat_A1[(num_pass+1):length(sumstat_A1)], function(x) {
      if (x == "ATG") {
        return("TAC")
      } else if (x == "TAC") {
        return("ATG")
      } else if (x == "GACA") {
        return("CTGT")
      } else if (x == "CTAA") {
        return("GATT")
      }
    })))
  }

  # Info SNPs
  info_A1 <- lapply(sumstat_A1[1:num_pass], function(x) {
    if(runif(1) < 0.2) {
      # flip a small proportion of the alleles
      if (x == "A") {
        return("T")
      } else if (x == "T") {
        return("A")
      } else if (x == "G") {
        return("C")
      } else if (x == "C") {
        return("G")
      }
    } else {
      return(x)
    }
  })
  info_A2 <- sumstat_A2[1:num_pass]
  # Handle random flips
  info_A2[info_A1 != sumstat_A1[1:num_pass]] <- unlist(lapply(info_A2[info_A1 != sumstat_A1[1:num_pass]], function(x) {
    if (x == "A") {
      return("T")
    } else if (x == "T") {
      return("A")
    } else if (x == "G") {
      return("C")
    } else if (x == "C") {
      return("G")
    }
  }))

  # Create the rest of the alleles
  info_A1 <- unlist(c(info_A1, sample(c("A", "T", "G", "C"), n-num_pass, replace = TRUE)))
  info_A2 <- unlist(c(info_A2, lapply(info_A1[(num_pass+1):length(info_A1)], function(x) {
    if (x == "A") {
      return(sample(c("G", "C"), 1))
    } else if (x == "T") {
      return(sample(c("G", "C"), 1))
    } else if (x == "G") {
      return(sample(c("A", "T"), 1))
    } else if (x == "C") {
      return(sample(c("A", "T"), 1))
    }
  })))

  chromosome <- unlist(rep(sample(1:20, 1), n))
  snp_positions <- sample(1:1000000, n)
  ref_variants <- data.frame(
    chrom = chromosome,
    pos = snp_positions,
    A1 = info_A1,
    A2 = info_A2
  )
  target_data <- data.frame(
    chrom = chromosome,
    pos = snp_positions,
    A1 = sumstat_A1,
    A2 = sumstat_A2,
    beta = rnorm(n),
    z = rnorm(n)
  )

  return(list(target_data = target_data, ref_variants = ref_variants))
}

test_that("Check that we correctly remove stand ambiguous SNPs",{
  res <- create_allele_data(1, n=100, match_min_prop=0.8, ambiguous=TRUE)
  output <- allele_qc(
    res$target_data, res$ref_variants, "beta", match_min_prop = 0.2,
    TRUE, FALSE, TRUE)
  expect_equal(nrow(output$target_data_qced), 80)
})

test_that("Check that we correctly remove non-ACTG coding SNPs",{
  res <- create_allele_data(1, n=100, match_min_prop=0.4, non_actg=TRUE)
  output <- allele_qc(
    res$target_data, res$ref_variants, "beta", match_min_prop = 0.2,
    TRUE, FALSE, TRUE)
  expect_equal(nrow(output$target_data_qced), 40)
})

test_that("Check that execution stops if not enough variants are matched",{
  res <- create_allele_data(1, n=100, match_min_prop=0.1, ambiguous=TRUE)
  expect_error(allele_qc(
    res$target_data, res$ref_variants, "beta", match_min_prop = 0.2,
    TRUE, FALSE, TRUE), "Not enough variants have been matched.")
})

test_that("align_variant_names correctly aligns variant names", {
  # Test case 1: Matching variant names
  source1 <- c("1:123:A:C", "2:456:G:T", "3:789:C:A")
  reference1 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A")
  expected_aligned1 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A")
  expected_unmatched1 <- integer(0)
  
  result1 <- align_variant_names(source1, reference1)
  expect_equal(result1$aligned_variants, expected_aligned1)
  expect_equal(result1$unmatched_indices, expected_unmatched1)
  
  # Test case 2: Unmatched variant names
  source2 <- c("1:123:A:C", "2:456:G:T", "3:789:C:A", "4:101:G:C")
  reference2 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A")
  expected_aligned2 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A", "4:101:G:C")
  expected_unmatched2 <- 4
  
  result2 <- align_variant_names(source2, reference2)
  expect_equal(result2$aligned_variants, expected_aligned2)
  expect_equal(result2$unmatched_indices, expected_unmatched2)
  
  # Test case 3: Different variant name formats
  source3 <- c("1:123:A:C", "2:456_G_T", "3:789:C:A")
  reference3 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A")
  expected_aligned3 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A")
  expected_unmatched3 <- integer(0)
  
  result3 <- align_variant_names(source3, reference3)
  expect_equal(result3$aligned_variants, expected_aligned3)
  expect_equal(result3$unmatched_indices, expected_unmatched3)
})

test_that("align_variant_names correctly aligns variant names with different flip patterns", {
  # Test case 4: Strand flip
  source4 <- c("1:123:A:C", "2:456:G:T", "3:789:C:A")
  reference4 <- c("1:123:T:G", "2:456:A:C", "3:789:C:A")
  expected_aligned4 <- c("1:123:T:G", "2:456:A:C", "3:789:C:A")
  expected_unmatched4 <- integer(0)
  
  result4 <- align_variant_names(source4, reference4)
  expect_equal(result4$aligned_variants, expected_aligned4)
  expect_equal(result4$unmatched_indices, expected_unmatched4)
  
  # Test case 5: Strand ambiguous variants
  source5 <- c("1:123:A:T", "2:456:G:C", "3:789:C:A")
  reference5 <- c("1:123:A:T", "2:456:G:C", "3:789:C:A")
  expected_aligned5 <- c("1:123:A:T", "2:456:G:C", "3:789:C:A")
  expected_unmatched5 <- integer(0)
  
  result5 <- align_variant_names(source5, reference5)
  expect_equal(result5$aligned_variants, expected_aligned5)
  expect_equal(result5$unmatched_indices, expected_unmatched5)
  
  # Test case 6: Sign flip
  source6 <- c("1:123:A:C", "2:456:G:T", "3:789:C:A")
  reference6 <- c("1:123:C:A", "2:456:T:G", "3:789:C:A")
  expected_aligned6 <- c("1:123:C:A", "2:456:T:G", "3:789:C:A")
  expected_unmatched6 <- integer(0)
  
  result6 <- align_variant_names(source6, reference6)
  expect_equal(result6$aligned_variants, expected_aligned6)
  expect_equal(result6$unmatched_indices, expected_unmatched6)
  
  # Test case 7: Strand and sign flip
  source7 <- c("1:123:A:C", "2:456:G:T", "3:789:C:A")
  reference7 <- c("1:123:G:T", "2:456:A:C", "3:789:C:A")
  expected_aligned7 <- c("1:123:G:T", "2:456:A:C", "3:789:C:A")
  expected_unmatched7 <- integer(0)
  
  result7 <- align_variant_names(source7, reference7)
  expect_equal(result7$aligned_variants, expected_aligned7)
  expect_equal(result7$unmatched_indices, expected_unmatched7)
  
  # Test case 8: Indels
  source8 <- c("1:123:A:C", "2:456:G:T", "3:789:C:A", "4:101:G:GATC")
  reference8 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A", "4:101:GATC:G")
  expected_aligned8 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A", "4:101:GATC:G")
  expected_unmatched8 <- integer(0)
  
  result8 <- align_variant_names(source8, reference8)
  expect_equal(result8$aligned_variants, expected_aligned8)
  expect_equal(result8$unmatched_indices, expected_unmatched8)
})

test_that("align_variant_names correctly aligns variant names with different chr prefix conventions", {
  # Test case 9: Original without chr prefix, reference with chr prefix
  source9 <- c("1:123:A:C", "2:456:G:T", "3:789:C:A")
  reference9 <- c("chr1:123:A:C", "chr2:456:T:G", "chr3:789:C:A")
  expected_aligned9 <- c("chr1:123:A:C", "chr2:456:T:G", "chr3:789:C:A")
  expected_unmatched9 <- integer(0)
  
  result9 <- align_variant_names(source9, reference9)
  expect_equal(result9$aligned_variants, expected_aligned9)
  expect_equal(result9$unmatched_indices, expected_unmatched9)
  
  # Test case 10: Original with chr prefix, reference without chr prefix
  source10 <- c("chr1:123:A:C", "chr2:456:G:T", "chr3:789:C:A")
  reference10 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A")
  expected_aligned10 <- c("1:123:A:C", "2:456:T:G", "3:789:C:A")
  expected_unmatched10 <- integer(0)
  
  result10 <- align_variant_names(source10, reference10)
  expect_equal(result10$aligned_variants, expected_aligned10)
  expect_equal(result10$unmatched_indices, expected_unmatched10)
})
