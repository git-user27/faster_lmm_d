/*
   This code is part of faster_lmm_d and published under the GPLv3
   License (see LICENSE.txt)

   Copyright © 2017 - 2018 Prasun Anand & Pjotr Prins
*/

module faster_lmm_d.lm;

import core.stdc.stdlib : exit;
import core.stdc.time;

import std.algorithm;
import std.conv;
import std.exception;
import std.file;
import std.math;
import std.parallelism;
import std.algorithm: min, max, reduce, countUntil, canFind;
alias mlog = std.math.log;
import std.process;
import std.range;
import std.stdio;
alias fwrite = std.stdio.write;
import std.typecons;
import std.experimental.logger;
import std.string;

import faster_lmm_d.dmatrix;
import faster_lmm_d.gemma_lmm;
import faster_lmm_d.gemma_param;
import faster_lmm_d.helpers;
import faster_lmm_d.optmatrix;

import gsl.permutation;
import gsl.rng;
import gsl.randist;
import gsl.cdf;

void lm_write_files() {
  // define later
  string path_out = "";
  string file_out = "";
  string file_gene;
  SUMSTAT[] sumStat;
  SNPINFO[] snpInfo;
  int[] indicator_snp;
  int a_mode;
  size_t ni_test;

  string file_str = path_out ~ "/" ~ file_out ~ ".assoc.txt";

  if (file_gene != "") {
    fwrite("geneID\t");

    if (a_mode == 51) {
      fwrite("beta\tse\tp_wald\n");
    } else if (a_mode == 52) {
      fwrite("p_lrt\n");
    } else if (a_mode == 53) {
      fwrite("beta\tse\tp_score\n");
    } else if (a_mode == 54) {
      fwrite("beta\tse\tp_wald\tp_lrt\tp_score\n");
    } else {
    }

    for (size_t t = 0; t < sumStat.length; ++t) {
      fwrite(snpInfo[t].rs_number, "\t");

      if (a_mode == 51) {
        fwrite(sumStat[t].beta, "\t", sumStat[t].se, "\t", sumStat[t].p_wald, "\n");
      } else if (a_mode == 52) {
        fwrite(sumStat[t].p_lrt, "\n");
      } else if (a_mode == 53) {
        fwrite(sumStat[t].beta, "\t", sumStat[t].se, "\t", sumStat[t].p_score, "\n");
      } else if (a_mode == 54) {
        fwrite(sumStat[t].beta, "\t", sumStat[t].se, "\t", sumStat[t].p_wald, "\t",
              sumStat[t].p_lrt, "\t", sumStat[t].p_score);
      } else {
      }
    }
  } else {
    fwrite("chr",
          "\t",
          "rs",
          "\t",
          "ps",
          "\t",
          "n_mis",
          "\t",
          "n_obs",
          "\t",
          "allele1",
          "\t",
          "allele0",
          "\t",
          "af",
          "\t");

    if (a_mode == 51) {
      fwrite("beta",
            "\t",
            "se",
            "\t",
            "p_wald", 
            "\n");
    } else if (a_mode == 52) {
      fwrite("p_lrt", "\n");
    } else if (a_mode == 53) {
      fwrite("beta",
            "\t",
            "se",
            "\t",
            "p_score",
            "\n");
    } else if (a_mode == 54) {
      fwrite("beta",
            "\t",
            "se",
            "\t",
            "p_wald",
            "\t",
            "p_lrt",
            "\t",
            "p_score");
    } else {
    }

    size_t t = 0;
    for (size_t i = 0; i < snpInfo.length; ++i) {
      if (indicator_snp[i] == 0) {
        continue;
      }

      fwrite(snpInfo[i].chr, "\t", snpInfo[i].rs_number, "\t", 
            snpInfo[i].base_position, "\t", snpInfo[i].n_miss, "\t",
            ni_test - snpInfo[i].n_miss, "\t", snpInfo[i].a_minor, "\t",
            snpInfo[i].a_major, "\t", snpInfo[i].maf,"\t");

      if (a_mode == 51) {
        fwrite(sumStat[t].beta, "\t", sumStat[t].se, "\t", sumStat[t].p_wald, "\n");
      } else if (a_mode == 52) {
        fwrite(sumStat[t].p_lrt, "\n");
      } else if (a_mode == 53) {
        fwrite(sumStat[t].beta, "\t", sumStat[t].se, "\t", sumStat[t].p_score, "\n");
      } else if (a_mode == 54) {
        fwrite(sumStat[t].beta, "\t", sumStat[t].se, "\t", sumStat[t].p_wald, "\t",
              sumStat[t].p_lrt, "\t", sumStat[t].p_score, "\n");
      } else {
      }
      t++;
    }
  }

  return;
}

void CalcvPv(const DMatrix WtWi, const DMatrix Wty,
             const DMatrix Wtx, const DMatrix y, const DMatrix x,
             double xPwy, double xPwx) {
  size_t c_size = Wty.size;
  double d;

  xPwx = vector_ddot(x, x);
  xPwy = vector_ddot(x, y);
  DMatrix WtWiWtx = matrix_mult(WtWi, Wtx);

  d = vector_ddot(WtWiWtx, Wtx);
  xPwx -= d;

  d = vector_ddot(WtWiWtx, Wty);
  xPwy -= d;

  return;
}

void CalcvPv(const DMatrix WtWi, const DMatrix Wty, const DMatrix y,
             double yPwy) {
  size_t c_size = Wty.size;
  double d;

  yPwy = vector_ddot(y, y);
  DMatrix WtWiWty = matrix_mult(WtWi, Wty);

  d = vector_ddot(WtWiWty, Wty);
  yPwy -= d;

  return;
}

// Calculate p-values and beta/se in a linear model.
void LmCalcP(const size_t test_mode, const double yPwy, const double xPwy,
             const double xPwx, const double df, const size_t n_size,
             double beta, double se, double p_wald, double p_lrt,
             double p_score) {
  double yPxy = yPwy - xPwy * xPwy / xPwx;
  double se_wald, se_score;

  beta = xPwy / xPwx;
  se_wald = sqrt(yPxy / (df * xPwx));
  se_score = sqrt(yPwy / (to!double(n_size) * xPwx));

  p_wald = gsl_cdf_fdist_Q(beta * beta / (se_wald * se_wald), 1.0, df);
  p_score = gsl_cdf_fdist_Q(beta * beta / (se_score * se_score), 1.0, df);
  p_lrt = gsl_cdf_chisq_Q(to!double(n_size) * (mlog(yPwy) - mlog(yPxy)), 1);

  if (test_mode == 3) {
    se = se_score;
  } else {
    se = se_wald;
  }

  return;
}

void lm_analyze_gene(const DMatrix W, const DMatrix x) {
  string file_gene;
  int a_mode;
  size_t ni_test, ng_total;
  int[] indicator_idv, indicator_snp;
  SUMSTAT[] sumStat;
  SNPINFO[] snpInfo;

  writeln("entering lm_analyze_gene");
  File infile = File(file_gene);

  string line;

  double beta = 0, se = 0, p_wald = 0, p_lrt = 0, p_score = 0;
  int c_phen;
  string rs; // Gene id.
  double d;

  // Calculate some basic quantities.
  double yPwy, xPwy, xPwx;
  double df = to!double(W.shape[0]) - to!double(W.shape[1]) - 1.0;

  DMatrix y; // = gsl_vector_alloc(W,shape[0]);

  gsl_permutation *pmt = gsl_permutation_alloc(W.shape[1]);

  DMatrix WtW = matrix_mult(W.T, W);
  DMatrix WtWi = WtW.inverse();

  DMatrix Wtx =  matrix_mult(W.T, x);
  CalcvPv(WtWi, Wtx, x, xPwx);

  // Header.
  infile.readln();

  for (size_t t = 0; t < ng_total; t++) {
    line = infile.readln();
   
    auto ch_ptr = line.split("\t");
    rs = ch_ptr[0];

    c_phen = 0;
    for (size_t i = 0; i < indicator_idv.length; ++i) {
      if (indicator_idv[i] == 0) {
        continue;
      }

      d = to!double(ch_ptr[1]);
      y.elements[c_phen] = d;

      c_phen++;
    }

    // Calculate statistics.
    DMatrix Wty = matrix_mult(W.T, y);
    CalcvPv(WtWi, Wtx, Wty, x, y, xPwy, yPwy);
    LmCalcP(a_mode - 50, yPwy, xPwy, xPwx, df, W.shape[0], beta, se, p_wald,
            p_lrt, p_score);

    // Store summary data.
    SUMSTAT SNPs = SUMSTAT(beta, se, 0.0, 0.0, p_wald, p_lrt, p_score, -0.0);
    sumStat ~= SNPs;
  }

  gsl_permutation_free(pmt);

  return;
}

void lm_analyze_bimbam(const DMatrix W, const DMatrix y) {
  
  string file_geno;
  int a_mode;
  size_t ni_test, ni_total;
  int[] indicator_idv, indicator_snp;
  SUMSTAT[] sumStat;
  SNPINFO[] snpInfo;

  writeln("entering lm_analyze_bimbam");
  File infile = File(file_geno);

  string line;

  double beta = 0, se = 0, p_wald = 0, p_lrt = 0, p_score = 0;
  int n_miss, c_phen;
  double geno, x_mean;

  // Calculate some basic quantities.
  double yPwy, xPwy, xPwx;
  double df = to!double(W.shape[0]) - to!double(W.shape[1]) - 1.0;

  DMatrix x; // = gsl_vector_alloc(W->size1);
  DMatrix x_miss; // = gsl_vector_alloc(W->size1);

  gsl_permutation *pmt = gsl_permutation_alloc(W.shape[1]);

  DMatrix WtW = matrix_mult(W.T, W);
  DMatrix WtWi = WtW.inverse();

  DMatrix Wty = matrix_mult(W.T, y);
  CalcvPv(WtWi, Wty, y, yPwy);

  // Start reading genotypes and analyze.
  for (size_t t = 0; t < indicator_snp.length; ++t) {
    line = infile.readln();
   
    if (indicator_snp[t] == 0) {
      continue;
    }

    auto ch_ptr = line.split("\t")[3..$];

    x_mean = 0.0;
    c_phen = 0;
    n_miss = 0;
    x_miss = zeros_dmatrix(1, W.shape[0]);
    for (size_t i = 0; i < ni_total; ++i) {
      if (indicator_idv[i] == 0) {
        continue;
      }

      if (ch_ptr[0] == "NA") {
        x_miss.elements[c_phen] = 0.0;
        n_miss++;
      } else {
        geno = to!double(ch_ptr[0]);

        x.elements[c_phen] = geno;
        x_miss.elements[c_phen] = 1.0;
        x_mean += geno;
      }
      c_phen++;
    }

    x_mean /= to!double(ni_test - n_miss);

    for (size_t i = 0; i < ni_test; ++i) {
      if (x_miss.elements[i] == 0) {
        x.elements[i] = x_mean;
      }
      geno = x.elements[i];
    }

    // Calculate statistics.

    DMatrix Wtx = matrix_mult(W.T, x);
    CalcvPv(WtWi, Wty, Wtx, y, x, xPwy, xPwx);
    LmCalcP(a_mode - 50, yPwy, xPwy, xPwx, df, W.shape[0], beta, se, p_wald, p_lrt, p_score);

    // Store summary data.
    SUMSTAT SNPs = SUMSTAT(beta, se, 0.0, 0.0, p_wald, p_lrt, p_score, -0.0);
    sumStat ~= SNPs;
  }

  gsl_permutation_free(pmt);

  return;
}

void lm_analyze_plink(const DMatrix W, const DMatrix y) {
  
  string file_bfile;
  size_t ni_total, ni_test;
  int a_mode;
  int[] indicator_snp, indicator_idv;
  SUMSTAT[] sumStat;
  SNPINFO[] snpInfo;

  writeln("entering lm_analyze_plink");

  string file_bed = file_bfile ~ ".bed";
  File infile = File(file_bed);

  char ch;
  int[] b;

  double beta = 0, se = 0, p_wald = 0, p_lrt = 0, p_score = 0;
  int n_bit, n_miss, ci_total, ci_test;
  double geno, x_mean;

  // Calculate some basic quantities.
  double yPwy, xPwy, xPwx;
  double df = to!double(W.shape[0]) - to!double(W.shape[1]) - 1.0;

  DMatrix x; // = gsl_vector_alloc(W->size1);

  gsl_permutation *pmt = gsl_permutation_alloc(W.shape[1]);

  DMatrix WtW = matrix_mult(W.T, W);
  DMatrix WtWi = WtW.inverse;

  DMatrix Wty = matrix_mult(W.T, y);
  CalcvPv(WtWi, Wty, y, yPwy);

  // Calculate n_bit and c, the number of bit for each SNP.
  if (ni_total % 4 == 0) {
    n_bit = to!int(ni_total) / 4;
  } else {
    n_bit = to!int(ni_total) / 4 + 1;
  }

  // Print the first three magic numbers.
  for (int i = 0; i < 3; ++i) {
    //infile.read(ch, 1);  // TODO: FIXME
    //b = ch;
  }

  for(size_t t = 0; t < snpInfo.length; ++t) {
    if (indicator_snp[t] == 0) {
      continue;
    }

    // n_bit, and 3 is the number of magic numbers.
    infile.seek(t * n_bit + 3);

    // Read genotypes.
    x_mean = 0.0;
    n_miss = 0;
    ci_total = 0;
    ci_test = 0;
    for (int i = 0; i < n_bit; ++i) {
      //infile.read(ch, 1);
      //b = ch;  // TODO: FIXME

      // Minor allele homozygous: 2.0; major: 0.0;
      for (size_t j = 0; j < 4; ++j) {
        if ((i == (n_bit - 1)) && ci_total == ni_total) {
          break;
        }
        if (indicator_idv[ci_total] == 0) {
          ci_total++;
          continue;
        }

        if (b[2 * j] == 0) {
          if (b[2 * j + 1] == 0) {
            x.elements[ci_test] = 2;
            x_mean += 2.0;
          } else {
            x.elements[ci_test] = 1;
            x_mean += 1.0;
          }
        } else {
          if (b[2 * j + 1] == 1) {
            x.elements[ci_test] = 0;
          } else {
            x.elements[ci_test] = -9;
            n_miss++;
          }
        }

        ci_total++;
        ci_test++;
      }
    }

    x_mean /= to!double(ni_test - n_miss);

    for (size_t i = 0; i < ni_test; ++i) {
      geno = x.elements[i];
      if (geno == -9) {
        x.elements[i] = x_mean;
        geno = x_mean;
      }
    }

    // Calculate statistics.

    DMatrix Wtx = matrix_mult(W.T, x);
    CalcvPv(WtWi, Wty, Wtx, y, x, xPwy, xPwx);
    LmCalcP(a_mode - 50, yPwy, xPwy, xPwx, df, W.shape[0], beta, se, p_wald, p_lrt, p_score);

    // store summary data
    SUMSTAT SNPs = SUMSTAT(beta, se, 0.0, 0.0, p_wald, p_lrt, p_score, -0.0);
    sumStat ~= SNPs;
  }

  gsl_permutation_free(pmt);
  return;
}

// Make sure that both y and X are centered already.
void MatrixCalcLmLR(const DMatrix X, const DMatrix y,
                    double[size_t] pos_loglr) {
  double yty, xty, xtx, log_lr;
  yty = vector_ddot(y, y);

  for (size_t i = 0; i < X.shape[1]; ++i) {
    //gsl_vector_const_view
    DMatrix X_col = get_col(X, i);
    xtx = vector_ddot(X_col, X_col);
    xty = vector_ddot(X_col, y);

    log_lr = 0.5 * to!double(y.size) * (mlog(yty) - mlog(yty - xty * xty / xtx));
    // TODO
    //pos_loglr ~= (make_pair(i, log_lr));
  }

  return;
}
