#ifndef QTL_ENRICHMENT_HPP
#define QTL_ENRICHMENT_HPP
#include <RcppArmadillo.h> // need to include this before RcppGSL otherwise it complains about conflicts
#include <vector>
#include <string>
#include <map>
#include <memory>
#include <random>
#include <omp.h>
#include <cmath>
#include <cstdio>

// Enable C++11
// [[Rcpp::plugins(cpp11)]]
// Enable openmp
// [[Rcpp::plugins(openmp)]]
// Import Armadillo
// [[Rcpp::depends(RcppArmadillo)]]

class SuSiEFit {
public:
std::vector<std::string> variable_names;
arma::mat alpha;
std::vector<double> prior_variance;

SuSiEFit(SEXP r_susie_fit) {
	Rcpp::List susie_fit(r_susie_fit);

	Rcpp::NumericVector pip_vec = Rcpp::as<Rcpp::NumericVector>(susie_fit["pip"]);
	// std::vector<double> pip = Rcpp::as<std::vector<double> >(pip_vec);
	variable_names = Rcpp::as<std::vector<std::string> >(pip_vec.names());
	alpha = Rcpp::as<arma::mat>(susie_fit["alpha"]);
	prior_variance = Rcpp::as<std::vector<double> >(susie_fit["prior_variance"]);

	if (alpha.n_rows != prior_variance.size()) {
		Rcpp::stop("The number of rows in alpha must match the length of prior_variance.");
	}

	// Check if all elements in prior_variance are not greater than 0
	if (std::all_of(prior_variance.begin(), prior_variance.end(), [](double x) {
			return x <= 0;
		})) {
		Rcpp::stop("At least one element in prior_variance must be greater than 0.");
	}

	// Filter out rows with prior_variance = 0
	std::vector<arma::uword> valid_rows;
	for (size_t i = 0; i < prior_variance.size(); ++i) {
		if (prior_variance[i] > 0) {
			valid_rows.push_back(i);
		}
	}
	alpha = alpha.rows(arma::uvec(valid_rows));
	prior_variance.erase(std::remove(prior_variance.begin(), prior_variance.end(), 0), prior_variance.end());

	// Add a check to make sure each row of alpha sums to 1
	for (arma::uword i = 0; i < alpha.n_rows; ++i) {
		double row_sum = arma::sum(alpha.row(i));
		if (std::abs(row_sum - 1.0) > 1e-6) {
			Rcpp::stop("Row " + std::to_string(i + 1) + " of single effect PIP matrix (alpha) does not sum to 1. It is: " + std::to_string(row_sum));
		}
	}
}

std::vector<std::string> impute_qtn(std::mt19937 &gen) const {
	std::vector<std::string> qtn_names;

	for (arma::uword i = 0; i < alpha.n_rows; ++i) {
		std::vector<double> alpha_row(alpha.colptr(i), alpha.colptr(i) + alpha.n_cols);
		std::discrete_distribution<> dist(alpha_row.begin(), alpha_row.end());
		int random_index = dist(gen);
		qtn_names.push_back(variable_names[random_index]);
	}

	return qtn_names;
}
};

std::vector<double> filter_outliers(
    const std::vector<double>& estimates,
    const std::vector<double>& variances,
    double prior_variance,
    double threshold = 3.0) 
{
    double mean = 0.0;
    double sd = 0.0;
    std::vector<double> shrinkage_ests;

    // Calculate shrinkage estimates and mean
    for(size_t i = 0; i < estimates.size(); ++i) {
        double shrinkage = (estimates[i] * prior_variance) / 
                          (prior_variance + variances[i]);
        shrinkage_ests.push_back(shrinkage);
        mean += shrinkage;
    }
    mean /= estimates.size();

    // Calculate standard deviation
    for(size_t i = 0; i < shrinkage_ests.size(); ++i) {
        sd += pow(shrinkage_ests[i] - mean, 2);
    }
    sd = sqrt(sd / (shrinkage_ests.size() - 1));

    // Filter outliers
    std::vector<double> filtered;
    for(size_t i = 0; i < estimates.size(); ++i) {
        if(fabs(shrinkage_ests[i] - mean) <= threshold * sd) {
            filtered.push_back(estimates[i]);
        }
    }

    return filtered;
}

std::vector<double> run_EM(
	const std::vector<double> &gwas_pip,
	const std::vector<int> &   annotation_vector,
	double                     pi_gwas,
	double                     pi_qtl,
	double                     total_snp,
	int                        max_iter = 1000,
	double                     a1_tol = 0.01)
{
	double a0 = log(pi_gwas / (1 - pi_gwas));
	double a1 = 0;
	double var0 = 0;
	double var1 = 0;
	double r0, r1;
	r0 = r1 = exp(a0);
	double r_null = pi_gwas / (1 - pi_gwas);
	int iter = 0;

	while (true) {
		iter++;
		// E step
		double pseudo_count = 1.0;
		double e0g0 = pseudo_count * (1 - pi_gwas) * (1 - pi_qtl);
		double e0g1 = pseudo_count * (1 - pi_qtl) * pi_gwas;
		double e1g0 = pseudo_count * (1 - pi_gwas) * pi_qtl;
		double e1g1 = pseudo_count * pi_gwas * pi_qtl;

		for (size_t i = 0; i < gwas_pip.size(); i++) {
			double val = gwas_pip[i];
			if (val == 1)
				val = 1 - 1e-8;
			// posterior ratio
			val = val / (1 - val);
			// val/r_null is marginal likelihood/bayes factor
			if (annotation_vector[i] == 0) {
				val = r0 * (val / r_null);
				// updated posterior with current prior given eqtl = 0
				val = val / (1 + val);
				e0g1 += val;
				e0g0 += 1 - val;
			}

			if (annotation_vector[i] == 1) {
				val = r1 * (val / r_null);
				// updated posterior with current prior given eqtl = 1
				val = val / (1 + val);
				e1g1 += val;
				e1g0 += 1 - val;
			}
		}

		e0g0 += total_snp - (e0g0 + e0g1 + e1g0 + e1g1);

		double a1_new = log(e1g1 * e0g0 / (e1g0 * e0g1));
		a1 = a1_new;
		a0 = log(e0g1 / e0g0); // a0 = log((e0g1+1)/(e0g0+1));
		r0 = exp(a0);
		r1 = exp(a0 + a1);
		var1 = (1.0 / e0g0 + 1.0 / e1g0 + 1.0 / e1g1 + 1.0 / e0g1);
		var0 = (1.0 / e0g1 + 1.0 / e0g0);

		if (fabs(a1_new - a1) < a1_tol || iter >= max_iter) {
			break;
		}
		if (iter % 100 == 0) {
			Rcpp::Rcout << "EM Iteration " << iter << ": a0 = " << a0 << ", a1 = " << a1 << std::endl;
		}
	}
	if (iter == max_iter) {
		Rcpp::Rcout << "WARNING: EM algorithm did not converge after " << iter << "iterations!" << std::endl;
	}

	std::vector<double> av;
	av.push_back(a0);
	av.push_back(a1);
	av.push_back(var0);
	av.push_back(var1);

	return av;
}

std::map<std::string, double> qtl_enrichment_workhorse(
	const std::vector<SuSiEFit> &   qtl_susie_fits,
	const std::vector<double> &     gwas_pip,
	const std::vector<std::string> &gwas_variable_names,
	double                          pi_gwas,
	double                          pi_qtl,
	int                             ImpN,
	double                          shrinkage_lambda,
	int                             num_threads = 4)
{

	std::vector<double> a0_vec(ImpN, 0.0);
	std::vector<double> v0_vec(ImpN, 0.0);
	std::vector<double> a1_vec(ImpN, 0.0);
	std::vector<double> v1_vec(ImpN, 0.0);

	std::map<std::string, int> gwas_variant_index;

	for (size_t i = 0; i < gwas_variable_names.size(); ++i) {
		gwas_variant_index[gwas_variable_names[i]] = i;
	}

	// pi_gwas = sum(gwas_pip) / total_snp
	double total_snp = std::accumulate(gwas_pip.begin(), gwas_pip.end(), 0.0) / pi_gwas;

	Rcpp::Rcout << "Fine-mapped GWAS and QTL data loaded successfully for enrichment analysis!" << std::endl;

	#pragma omp parallel for num_threads(num_threads)
	for (int k = 0; k < ImpN; k++) {
		// Initialize the RNG for this thread
		std::random_device rd;
		std::mt19937 gen(rd());

		// Use QTL to annotate GWAS variants
		std::vector<int> annotation_vector(gwas_pip.size(), 0);
		int missing_qtl_count = 0; // Counter for xQTL not in gwas_variant_index
		int total_qtl_count = 0;

		for (size_t i = 0; i < qtl_susie_fits.size(); i++) {
			std::vector<std::string> variants = qtl_susie_fits[i].impute_qtn(gen);
			for (const auto &variant : variants) {
				auto it = gwas_variant_index.find(variant);
				if (it != gwas_variant_index.end()) {
					// Update annotation_vector only if variant is found
					annotation_vector[it->second] = 1;
				} else {
					++missing_qtl_count;
				}
			}
			total_qtl_count += variants.size();
		}
		// Calculate the proportion of missing variants
		double missing_variant_proportion = static_cast<double>(missing_qtl_count) / total_qtl_count;
		std::vector<double> rst = run_EM(gwas_pip, annotation_vector, pi_gwas, pi_qtl, total_snp);

	#pragma omp critical
		{
			a0_vec[k] = rst[0];
			a1_vec[k] = rst[1];
			v0_vec[k] = rst[2];
			v1_vec[k] = rst[3];
			Rcpp::Rcout << "Proportion of xQTL missing from GWAS variants: " << missing_variant_proportion << " in MI round " << k << std::endl;
		}
	}

	Rcpp::Rcout << "EM updates completed!" << std::endl;

	// Apply outlier filtering if shrinkage is specified
	std::vector<double> filtered_a1;
	std::vector<double> filtered_v1;
	if (shrinkage_lambda > 0) {
		filtered_a1 = filter_outliers(a1_vec, v1_vec, 1.0/shrinkage_lambda);
		filtered_v1.reserve(filtered_a1.size());
		for(size_t i = 0; i < a1_vec.size(); ++i) {
			if(std::find(filtered_a1.begin(), filtered_a1.end(), a1_vec[i]) != filtered_a1.end()) {
				filtered_v1.push_back(v1_vec[i]);
			}
		}
	} else {
		filtered_a1 = a1_vec;
		filtered_v1 = v1_vec;
	}

	double a0_est = 0;
	double a1_est = 0;
	double var0 = 0;
	double var1 = 0;
	for (size_t k = 0; k < filtered_a1.size(); k++) {
		a0_est += a0_vec[k];
		a1_est += filtered_a1[k];
		var0 += v0_vec[k];
		var1 += filtered_v1[k];
	}
	a0_est /= filtered_a1.size();
	a1_est /= filtered_a1.size();

	double bv0 = 0;
	double bv1 = 0;
	for (size_t k = 0; k < filtered_a1.size(); k++) {
		bv0 += pow(a0_vec[k] - a0_est, 2.0);
		bv1 += pow(filtered_a1[k] - a1_est, 2.0);
	}
	bv0 /= (filtered_a1.size() - 1);
	bv1 /= (filtered_a1.size() - 1);
	var0 /= filtered_a1.size();
	var1 /= filtered_a1.size();

	double sd0 = sqrt(var0 + bv0 * (filtered_a1.size() + 1) / filtered_a1.size());
	double sd1 = sqrt(var1 + bv1 * (filtered_a1.size() + 1) / filtered_a1.size());

	double a1_est_ns = a1_est;
	double sd1_ns = sd1;

	// Apply shrinkage
	double pv = (shrinkage_lambda == 0) ? -1.0 : 1.0/shrinkage_lambda;
	if (pv > 0) {
		a1_est = (a1_est_ns * pv) / (pv + sd1_ns * sd1_ns);
		sd1 = sqrt( 1.0 / (1.0 / pv + 1 / (sd1_ns * sd1_ns)) );
	}

	a0_est = log(pi_gwas / (1 + pi_qtl * exp(a1_est) - pi_qtl - pi_gwas));

	double pi1_ne = exp(a0_est) / (1 + exp(a0_est));
	double pi1_e = exp(a0_est + a1_est) / (1 + exp(a0_est + a1_est));

	double p1 = (1 - pi_qtl) * pi1_ne;
	double p2 = pi_qtl / (1 + exp(a0_est + a1_est));
	double p12 = pi_qtl * pi1_e;

	// Create the map to store output
	std::map<std::string, double> output_map;
	output_map["Intercept"] = a0_est;
	output_map["sd (intercept)"] = sd0;
	output_map["Enrichment (no shrinkage)"] = a1_est_ns;
	output_map["Enrichment (w/ shrinkage)"] = a1_est;
	output_map["sd (no shrinkage)"] = sd1_ns;
	output_map["sd (w/ shrinkage)"] = sd1;
	output_map["Alternative (coloc) p1"] = p1;
	output_map["Alternative (coloc) p2"] = p2;
	output_map["Alternative (coloc) p12"] = p12;
	output_map["Effective MI rounds"] = static_cast<double>(filtered_a1.size());

	return output_map;
}

#endif // QTL_ENRICHMENT_HPP
