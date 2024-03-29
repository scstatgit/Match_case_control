/***********************************************************************/
/* Program: PSMatch_Multi.sas
/*
/* Platform: SAS 9.4
/*
/* Author: Kathy H. Fraeman
/*
/* Drug/Protocol: Generalized SAS Macro
/* 
/* Description: Does N:1 propensity score matching within specified 
/* absolute differences (radius) of propensity score
/*
/* Can optimize on either number of matches, or closeness 
/* of matches, or no optimization
/***********************************************************************/
%macro psmatch_multi(subj_dsn =, /* Data set with subject data */
subj_idvar=, /* Subject ID variable in &SUBJ_DSN */
subj_psvar=, /* Propensity Score variable in &SUBJ_DSN */
cntl_dsn=, /* Data set with control data */
cntl_idvar=, /* Control ID variable in data set &CNTL_DSN */
cntl_psvar=, /* Propensity Score variable in &CNTL_DSN */
group=, /* must coded disease as 1, healthy as 0 */
match_dsn=, /* Output data set */
match_ratio=, /* Number of matches per subject */
score_diff=, /* Maximum allowable absolute differences between propensity scores*/
opt=none, /* Type of matching optimization -- by number of matches( = num), by closeness ( = close), or default none ( = none) */
seed=1234567890) /* Optional seed for random number generator */
;
/*******************************************************************/
/* Delete final matched pairs dataset, if exists from a prior run
/*******************************************************************/
PROC DATASETS nolist;
delete __final_matched_pairs;
run;
quit;
/********************************************/
/* Make all internal macro variables local
/********************************************/
%local __dsid __varnum __cntl_type __rc __num;
/**********************************************/
/* Control ID variable (numeric or character)
/**********************************************/
%let __dsid = %sysfunc(open(&cntl_dsn,i));
%let __varnum = %sysfunc(varnum(&__dsid, &cntl_idvar));
%let __cntl_type = %sysfunc(vartype(&__dsid, &__varnum));
%let __rc = %sysfunc(close(&__dsid));
%put &__cntl_type;
/**************************/
/* Subject Matching Data
/**************************/
DATA __subjmatch (keep = &subj_idvar &subj_psvar);
set &subj_dsn;
run;
/**************************/
/* Control Matching Data
/**************************/
DATA __contmatch (keep = &cntl_idvar &cntl_psvar);
set &cntl_dsn;
run;
/************************************************************/
/* Find all possible matches between subjects and controls
/* Propensity scores must match within +/- &match (radius)
/************************************************************/
PROC SQL;
create table __matches0 as
select
s.&subj_idvar as subj_idvar,
c.&cntl_idvar as cntl_idvar,
s.&subj_psvar as subj_score,
c.&cntl_psvar as cntl_score,
abs(s.&subj_psvar - c.&cntl_psvar) as diff_score
from __subjmatch s left join __contmatch c
on abs(s.&subj_psvar - c.&cntl_psvar) <= &score_diff 
order by subj_idvar;
quit;
/*************************************/
/* Data set of all possible matches
/*************************************/
DATA __possible_matches;
set __matches0;
/*-----------------------------------------*/
/* Create a random number for each match
/*-----------------------------------------*/
call streaminit(&seed); 
rand_num = rand('uniform');
/*-----------------------------------------------*/
/* Remove subjects who had no possible matches
/*-----------------------------------------------*/
%if &__cntl_type = C %then %do;
if cntl_idvar ^= '';
%end;
%else %if &__cntl_type = N %then %do;
if cntl_idvar ^= .;
%end;
/*--------------------------------------------*/
/* Round DIFF_SCORE to an order of magnitude
/*--------------------------------------------*/
%if &opt = close %then %do;
if . < diff_score < .000000001 then 
sort_diff_score = .000000001;
else if .000000001 <= diff_score < .00000001 then 
sort_diff_score = round(diff_score, .000000001);
else if .00000001 <= diff_score < .0000001 then 
sort_diff_score = round(diff_score, .00000001);
else if .0000001 <= diff_score < .000001 then 
sort_diff_score = round(diff_score, .0000001);
else if .000001 <= diff_score < .00001 then 
sort_diff_score = round(diff_score, .000001);
else if .00001 <= diff_score < .0001 then 
sort_diff_score = round(diff_score, .00001);
else if .0001 <= diff_score < .001 then 
sort_diff_score = round(diff_score, .0001);
else if .001 <= diff_score < .01 then 
sort_diff_score = round(diff_score, .001);
else if .01 <= diff_score < .1 then 
sort_diff_score = round(diff_score, .01);
else if diff_score >= .1 then 
sort_diff_score = round(diff_score, .1);
%end;
/*---------------------------*/
/* Create a dummy variable
/*---------------------------*/
n = 1;

run;
/******************************************************************/
/* Find the number of potential control matches for each subject
/******************************************************************/
PROC FREQ data=__possible_matches noprint;
tables subj_idvar / out=__matchfreq (keep = subj_idvar count);
run;
DATA __matches_freq;
merge __possible_matches
__matchfreq;
by subj_idvar;
/*------------------------------------------------------------*/
/* Only keep subjects with minimum number of possible matches
/*------------------------------------------------------------*/
if count >= &match_ratio;
run;
PROC DATASETS nolist;
delete __matches0;
run;
quit;
/*****************************************************************/
/* Count the number of entries in the file of possible matches
/*****************************************************************/
%let __dsid = %sysfunc(open(__matches_freq,i));
%let __num = %sysfunc(attrn(&__dsid,nobs));
%let __rc = %sysfunc(close(&__dsid));
%do %while (&__num >= 1); 
PROC SORT data=__matches_freq;
by %if &opt = num %then %do; 
count 
%end; 
%else %if &opt = close %then %do; 
sort_diff_score 
%end;
rand_num subj_idvar;
run;
/**************************************************************/
/* Get first randomly selected subject 
/* For options, with either the least number of matches or 
/* the closest match
/**************************************************************/
DATA __first_subj_idvar (keep = subj_idvar);
set __matches_freq;
by n;
if first.n;
run;
/**************************************/
/* Get all matches for that subject
/***************************************/
PROC SORT data=__matches_freq;
by subj_idvar %if &opt = num %then %do; 
count
%end; 
%else %if &opt = close %then %do; 
sort_diff_score 
%end;
rand_num;
run;
DATA __all_first_id;
merge __matches_freq
__first_subj_idvar (in=i);
by subj_idvar;
if i;
num + 1;
run;
DATA __new_matched_pairs (keep = subj_idvar cntl_idvar 
subj_score cntl_score);
set __all_first_id;

label subj_idvar = 
"Subject ID, original variable name &subj_idvar"
cntl_idvar = 
"Matched Control ID, original variable name &cntl_idvar"
subj_score = 
"Subject Propensity Score, original var name &subj_psvar"
cntl_score = 
"Matched Control Propensity Score, orig var &cntl_psvar"
;
if num <= &match_ratio;
run;
/******************************************/
/* Remove subjects with matched controls
/******************************************/
PROC SORT data=__new_matched_pairs (keep = subj_idvar) 
out=__new_matched_subj nodupkey;
by subj_idvar;
run;
DATA __match_remove_subj;
merge __possible_matches
__new_matched_subj (in=id);
by subj_idvar;
if ^id;
run;
/************************************************************/
/* Remove all matched pairs that include selected controls
/************************************************************/
PROC SORT data=__new_matched_pairs (keep = cntl_idvar) 
out=__remove_cont;
by cntl_idvar;
run;
PROC SORT data=__match_remove_subj;
by cntl_idvar;
run;

DATA __match_remove_cont;
merge __match_remove_subj
__remove_cont (in=id);
by cntl_idvar;
if ^id;
run;
PROC SORT data=__match_remove_cont out=__possible_matches;
by subj_idvar;
run;
/********************************************************/
/* Add new matched pairs to set of final matched pairs
/********************************************************/
PROC APPEND base=__final_matched_pairs data=__new_matched_pairs;
run;
/***************************************************************/
/* Find the number of potential control matches for each subject
/****************************************************************/
PROC FREQ data=__possible_matches noprint;
tables subj_idvar / out=__matchfreq (keep = subj_idvar 
count);
run;


DATA __matches_freq;
merge __possible_matches
__matchfreq;
by subj_idvar;
/*---------------------------------------------------------*/
/* Only keep subjects with the minimum number of matches
/*---------------------------------------------------------*/
if count >= &match_ratio;
run;
/********************************************************/
/* Determine number of remaining possible matched pairs
/********************************************************/
%let __dsid = %sysfunc(open(__matches_freq,i));
%let __num = %sysfunc(attrn(&__dsid,nobs));
%let __rc = %sysfunc(close(&__dsid)); 
%end; /* of " %do %while (&__num >= 1); */
/*****************************************************************/
/* Create final output data set with one observation for each 
/* original subject.
/* 
/* Variable names in output data set are:
/* SUBJ_IDVAR, SUBJ_SCORE, CNTL_IDVAR, CNTL_SCORE
/*
/* If no match for subject ID (SUBJ_IDVAR), then CNTL variables 
/* (CNTL_IDVAR, CNTL_SCORE) are missing.
/*****************************************************************/
PROC SORT data=__final_matched_pairs;
by subj_idvar subj_score;
run; 
DATA __subjmatch_orig;
set __subjmatch (rename= (&subj_idvar = subj_idvar 
&subj_psvar = subj_score));
run;
PROC SORT data=__subjmatch_orig;
by subj_idvar;
run;
DATA __propensity_socres_orig;
set propensity_scores (rename= (&subj_idvar = subj_idvar 
&subj_psvar = subj_score));
run;
PROC SORT data=__propensity_socres_orig;
by subj_idvar;
run;
DATA &match_dsn (label="Final Matched Pairs for PS Matching");
merge __final_matched_pairs
__subjmatch_orig;
by subj_idvar subj_score;
run;
DATA &match_dsn._vars_1 (label="Final Matched Pairs for PS Matching with Variables");
merge __final_matched_pairs(in=in1)
__propensity_socres_orig(in=in2);
by subj_idvar subj_score;
if in1 and in2;
run;
PROC SORT data=__final_matched_pairs;
by cntl_idvar;
run; 
DATA __propensity_socres_orig;
set propensity_scores (rename= (&cntl_idvar = cntl_idvar 
&cntl_psvar = cntl_score));
run;
PROC SORT data=__propensity_socres_orig;
by cntl_idvar;
run;
DATA &match_dsn._vars_2 (label="Final Matched Pairs for PS Matching with Variables");
merge __final_matched_pairs(in=in1)
__propensity_socres_orig(in=in2);
by cntl_idvar;
if in1 and in2;
run;
PROC SORT data=&match_dsn._vars_1;
by subj_idvar descending &group;
run;
PROC SORT data=&match_dsn._vars_2;
by subj_idvar descending &group;
run;
DATA &match_dsn._vars (drop=cntl_idvar subj_idvar subj_score cntl_score rename=(subj_idvar2=subj_idvar subj_score2=subj_score)
										label="Final Matched Pairs for PS Matching with Variables");
length subj_idvar2 seq &group subj_score2 8;
set &match_dsn._vars_1(in=in1) &match_dsn._vars_2(in=in2);
by subj_idvar;
if first.subj_idvar then do;
seq+1;
cntl_score=.;
end;
if in1 then cntl_idvar='';
if in2 then subj_idvar='';
subj_idvar2=coalesce(subj_idvar, cntl_idvar);
subj_score2=coalesce(cntl_score, subj_score);
label subj_idvar2 = 
"Subject ID, original variable name &subj_idvar"
subj_score2 = 
"Subject Propensity Score, original var name &subj_psvar"
;
run;
PROC SORT data=&match_dsn._vars nodupkey; by seq descending &group subj_idvar; run;
/***************************************************/
/* Delete all temporary datasets created by macro 
/***************************************************/
PROC DATASETS nolist;
delete __contmatch __final_matched_pairs __matches_freq0 
__matches_freq __match_pair0 __matchfreq 
__match_remove_cont __match_remove_subj 
__new_matched_pairs __subjmatch __subjmatch_orig 
__possible_matches __remove_cont 
__first_subj_idvar __all_first_id 
__new_matched_subj
&match_dsn._vars_1 &match_dsn._vars_2;
run;
quit; 
%mend psmatch_multi;


data ddd;
set sashelp.cars;
if Type = 'SUV' then group=1; else group=0;
id=_n_;
run;
PROC LOGISTIC data=ddd descending;
class origin;
model group = origin Invoice EngineSize Cylinders Horsepower MPG_city MPG_highway;
output out=propensity_scores pred = pscore;
run;


/********************************************************************/
/* Separate patients treated with the drug from untreated patients
/********************************************************************/
DATA prop_score_treated
prop_score_untreated;
set propensity_scores;
if group = 1 then output prop_score_treated;
else if group = 0 then output prop_score_untreated;
run;


/************************************************************************/
/* 1:1 Matching with an absolute difference between propensity scores
/* of 0.01, random matching (no value given for parameter OPT, defaults to
/* none
/************************************************************************/
%psmatch_multi(
subj_dsn = prop_score_treated,
subj_idvar = id,
subj_psvar = pscore,
cntl_dsn = prop_score_untreated, 
cntl_idvar = id,
cntl_psvar = pscore, 
group = group,
match_dsn = matched_pairs1, 
match_ratio = 1,
score_diff = 0.01
);


/************************************************************************/
/* 2:1 Matching with an absolute difference between propensity scores
/* of 0.05, matching optimized for number of matches
/************************************************************************/
%psmatch_multi(
subj_dsn = prop_score_treated,
subj_idvar = id,
subj_psvar = pscore,
cntl_dsn = prop_score_untreated, 
cntl_idvar = id,
cntl_psvar = pscore,
group = group,
match_dsn = matched_pairs2,
match_ratio = 2,
score_diff = 0.05
);


/************************************************************************/
/* 1:1 Matching with an absolute difference between propensity scores
/* of 0.001, matching optimized for the closeness of the matches
/************************************************************************/
%psmatch_multi(
subj_dsn = prop_score_treated,
subj_idvar = id,
subj_psvar = pscore,
cntl_dsn = prop_score_untreated, 
cntl_idvar = id,
cntl_psvar = pscore, 
group = group,
match_dsn = matched_pairs3, 
match_ratio = 1,
score_diff = 0.001
);


/************************************************************************/
/* 4:1 Matching with an absolute difference between propensity scores
/* of 0.01, matching optimized for number of matches
/************************************************************************/
%psmatch_multi(
subj_dsn = prop_score_treated,
subj_idvar = id,
subj_psvar = pscore,
cntl_dsn = prop_score_untreated, 
cntl_idvar = id,
cntl_psvar = pscore,
group = group,
match_dsn = matched_pairs4,
match_ratio = 4,
score_diff = 0.01
);
