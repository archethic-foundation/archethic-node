#include <stdio.h>
#include <stdlib.h>
#include <gmp.h>

#define TOLERANCE 0.000000001
#define MALICIOUS_RATE 0.9

void factorial(mpf_t res, int n)  
{  
  int i;
  mpf_t p;
  mpf_init_set_ui(p,1);

  for (i=1; i <= n ; ++i){
    mpf_mul_ui(p,p,i);
  }

  mpf_set(res, p);
  mpf_clear(p);
}  

// Combination: factorial(n) / ( factorial(r) * factorial(n-r) )
void combination(mpf_t comb, int n, int r) {
  mpf_t fact_n;
  mpf_init(fact_n);

  mpf_t fact_r;
  mpf_init(fact_r);

  mpf_t fact_n_minus_r;
  mpf_init(fact_n_minus_r);
  
  factorial(fact_n, n);
  factorial(fact_r, r);
  factorial(fact_n_minus_r, n - r);

  mpf_t fact_r_mul_fact_r_minus_r;
  mpf_init(fact_r_mul_fact_r_minus_r);
  mpf_mul(fact_r, fact_r, fact_n_minus_r);

  mpf_div(comb, fact_n, fact_r);

  mpf_clear(fact_n);
  mpf_clear(fact_r);
  mpf_clear(fact_n_minus_r);
  mpf_clear(fact_r_mul_fact_r_minus_r);
}

void hypergeometric_distribution(int nb_nodes) {
    int nb_malicious = nb_nodes * MALICIOUS_RATE;
    int nb_good = nb_nodes - nb_malicious;

    int n = 1;    
    
    mpf_t tolerance;
    
    mpf_init_set_d(tolerance, TOLERANCE);

    int abort = 0;

    #pragma omp parallel for schedule(dynamic) shared(abort)
    for (n = 1; n <= nb_nodes; n++) {

      #pragma omp flush(abort)
      if (abort == 0) {

        mpf_t sum;
        mpf_t sum_minus_1;

        mpf_init(sum);
        mpf_init(sum_minus_1);

        for (int k = 1; k <= nb_good; k++) {

          if (abort == 0) {
            if (n - k >= 0 && nb_good - k >= 0 && nb_malicious >= n - k) {

              mpf_t comb_nb_good_with_k;
              mpf_t comb_nb_malicious_with_n_minus_k;
              mpf_t comb_nb_nodes_with_n;
              mpf_init(comb_nb_good_with_k);
              mpf_init(comb_nb_malicious_with_n_minus_k);
              mpf_init(comb_nb_nodes_with_n);

              // combination(nb_good, k) * combination(nb_malicious, n - k ) / combination(nb_nodes, n)
              combination(comb_nb_good_with_k, nb_good, k);
              combination(comb_nb_malicious_with_n_minus_k, nb_malicious, n - k);

              mpf_mul(comb_nb_good_with_k, comb_nb_good_with_k, comb_nb_malicious_with_n_minus_k);
              combination(comb_nb_nodes_with_n, nb_nodes, n);
              mpf_div(comb_nb_good_with_k, comb_nb_good_with_k, comb_nb_nodes_with_n);

              mpf_add(sum, sum, comb_nb_good_with_k);
              mpf_ui_sub(sum_minus_1, 1, sum);

              if (mpf_cmp(sum_minus_1, tolerance) == -1) {
                #pragma omp critical                       
                {
                  if (abort == 0) {
                    printf("%d\r\n", n);
                    #pragma omp atomic write
                    abort = 1;
                    #pragma omp cancel for
                  }
                }
              }
              #pragma omp cancellation point for
            }
          }
        }
      }
    }
}

int main(int argc, char *argv[]) {

  if( argc == 2 ) {
    int nb_nodes = atoi(argv[1]);
     hypergeometric_distribution(nb_nodes);
  }

  return 0;
}