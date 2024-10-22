/*********************************************/
/* 											 */
/*  	using k-fold cross validation to	 */
/*  	  assess model generalizability 	 */
/*  										 */
/*			Harry Snart, SAS Institute		 */
/*  				October 2024			 */
/*  										 */
/*********************************************/

/* This script gives an example of:
- loading the HMEQ dataset
- performing a simple exploratory data analysis 
- performing a stepwise logistic regression
- assessing predictive accuracy on a test dataset
- assessing generalisability via k-fold cross validation on a hold out dataset
 */
ods graphics / reset;

options nodate nonumber; 

/* NOTE: uncomment the PROC TEMPLATE and ODS HTML5 statements to produce an HTML report instead of PDF report. */
 ods pdf file='<your-path>/Model Assessment with  K-Fold Cross Validation.pdf' noaccessible author='Harry Snart' dpi=300 nobookmarkgen nocontents title="Model Assessment with  K-Fold Cross Validation" notoc nopdfnote  subject="Advanced Analytics with SAS Viya" startpage=never ;  
/*
proc template;
   define style styles.mystyle;
      parent=styles.htmlblue;
         class pagebreak /
	     display=none;         
   end;
run; 

ods html5 file="<your-path>/Model Assessment with K-Fold Cross Validation.html" style=styles.mystyle;*/


/* 0 - Create CAS Session */

/* Here we create a CAS session, connecting to the SAS Viya in-memory engine. */

cas casauto;
caslib _all_ assign;


proc odstext; p "Model Assessment with K-Fold Cross Validation" / style=[color=navy fontsize=25pt just=c];
p "Harry Snart, SAS Institute" / style=[color=navy fontsize=18pt just=c];
p "October 2024" / style=[color=navy fontsize=18pt just=c];
run;

proc odstext; p "This document shows how K-Fold Cross Validation can be used to assess model goodness of fit with few holdout samples. We start by loading the HMEQ dataset which has a binary target of BAD. After performing a brief exploratory analysis we then perform oversampling on the event class and then partition the dataset into Train, Test and Validate. We then train a logistic regression model with stepwise selection and perform k-fold sampling on the holdout dataset to score each of the partitions in order to generate a distribution of model assessment scores." / style=[color=black fontsize=12pt just=c];
p '';
run;

/* 1 - Load Dataset into CAS */

/* Here we load the HMEQ.csv dataset directly into CAS using PROC IMPORT */

proc odstext; p "Load Dataset" / style=[color=navy fontsize=16pt just=c];
p "Here we load the dataset using PROC IMPORT then print via PROC PRINT" / style=[color=black fontsize=12pt just=c];
run;

proc import datafile='<your-path>/HMEQ.csv' dbms=csv out=casuser.hmeq;run;

proc print data=casuser.hmeq(obs=5) noobs l;title 'Sample of HMEQ Dataset';run;

/* 2 - Simple EDA */

/* The exploratory analysis is simple and for demonstration purposes. We can use PROC CORR to create a correlation matrix, and SGPLOT to plot key patterns in the data */

/* balance of target variable */

ods graphics / noborder;

proc odstext;p "Exploratory Data Analysis"/style=[color=navy fontsize=16pt just=c];
p "Here we perform an exploratory data analysis including variable correlation with PROC CORR, variable summary analysis with PROC CARDINALITY and visual analysis with PROC SGPLOT"/style=[color=black fontsize=12pt just=c];
run;

proc sql noprint ;create table tmp as select distinct bad as "Bad"n, count(*) as "Number of Observations"n from casuser.hmeq group by bad;quit;

proc print noobs l data=tmp;
title 'Check for class imbalance';
title2 "There is a class imbalance in the dataset which can be addressed with oversampling" ;
;run;

title2;


ods exclude all;
proc cardinality data=CASUSER.HMEQ outcard=casuser.varSummaryTemp 
		out=casuser.levelDetailTemp;
	freq BAD;
run;
ods exclude none;

proc print data=casuser.varSummaryTemp label noobs;
var _VARNAME_ _TYPE_ _CARDINALITY_ _NOBS_ _NMISS_ _MEAN_ _STDDEV_;
	title 'Variable Summary';
run;

ods noproctitle;
title 'Variable Correlation';
title2 'Variables such as Loan amount appear to have an explanatory power for Bad.';
proc corr data=casuser.hmeq plots(maxpoints=1000000)=matrix plots=matrix nomiss noprob nosimple nocorr  ; run;

title2;
/* ods pdf startpage=never; */

ods graphics / height=5in width=5in;

proc sgplot data=casuser.hmeq;
hbar reason / group=bad;
title 'Levels of character variable: Reason';
run;

proc sgplot data=casuser.hmeq;
hbar job / group=bad;
title 'Levels of character variable: Job';
run;

/* 3 - Partition Data with oversampling of event class */

/* Here we partition the data into a train/test/validate split. We actually use PROC PARTITION twice. The first time to reduce the dataset and retain an even split in event classes. 

We then use PROC PARTITION to create our analytical partitions. */

ods proctitle;

proc odstext ; p "Perform oversampling of event class"/style=[color=navy fontsize=16pt just=c];
p "Here we oversample the event class, 1, given that the exploratory analysis shows there is a class imbalance we do this using PROC PARTITION"/style=[color=black fontsize=12pt just=c];
run;


proc partition data=casuser.HMEQ event='1' eventprop=0.5 sampPctEvt=90 ;
	by BAD;
	output out=casuser.samples;
run;

/* visualize dataset balance */
proc sgplot data=casuser.samples;
hbar bad;title 'Oversampled Group';
run;

/* partition into train/test/validate with 70/15/15 split */

proc partition data=CASUSER.SAMPLES partind  samppct=50 samppct2=25;
	by BAD;
	output out=casuser.hmeq_part;
run;

data casuser.hmeq_part;
	set casuser.hmeq_part;

	if _PartInd_=0 then
		_PartInd_=3;
if _PartInd_ = 3 then PartName = 'Validate';
if _PartInd_ = 1 then PartName = 'Train';
if _PartInd_ = 2 then PartName = 'Test';

run;
/* note 0=train 1=test 2=validate */

proc sgplot data=casuser.hmeq_part;
hbar partname / group=bad;title 'Check number of observations by partition';run;
title;

/* 4 - Stepwise Logistic Regression */

/* retain only train/test */

data casuser.train_test;
set casuser.hmeq_part;
where partname ne 'Validate';
run;

data casuser.holdout;
set casuser.hmeq_part;
where partname eq 'Validate';
run;

/* create scoring file for model output */
filename sfile '<your-path>/score.sas';

proc odstext ; p "Create Logistic Regression Model"/style=[color=navy fontsize=16pt just=c];
p "Here we perform stepwise Logistic Regression using the Train and Test partitions using PROC LOGSELECT. The procedure prints summary statistics for both partitions."/style=[color=black fontsize=12pt just=c];
p "We also save the scoring code to a SAS file that we can then use to score the kfold partitions later."/style=[color=black fontsize=12pt just=c];
run;

/* Here we create our logistic regression using stepwise regression. Note that cross validation during model training is also an option for some of the Viya ML procs, here we are instead 
using cross validation for model assessment post-training. */

proc logselect data=CASUSER.TRAIN_TEST partfit ;
	partition role=PartName (test='Test') ;
	class REASON JOB;
	model BAD(event='1')=REASON JOB LOAN MORTDUE VALUE YOJ DEROG DELINQ CLAGE NINQ 
		CLNO DEBTINC / link=logit;
	selection method=stepwise
     (stop=sbc choose=sbc) hierarchy=none;
	code file=sfile ;
run;

/* 5 - Assess Model Fit */

/* score test dataset and assess goodness of fit */

/* we can score our logistic regression model easily by using the INCLUDE statement in a DataStep */
data casuser.test;
set casuser.train_test;
where partname = 'Test';
%include '<your-path>/score.sas';
p_good = 1-p_bad;
if p_good ne . and p_bad ne . then output;
run;

ods exclude all;
/* PROC ASSESS lets us calculate Lift/ROC statistics for our model */
proc assess data=CASUSER.TEST nbins=10 ncuts=10;
	target BAD / event="1" level=nominal;
	input P_BAD;
	fitstat pvar=P_GOOD / pevent="0" delimiter=',';
	ods output ROCInfo=WORK._roc_temp LIFTInfo=WORK._lift_temp;
run;
ods exclude none;

data _null_;
	set WORK._roc_temp(obs=1);
	call symput('AUC', round(C, 0.01));
run;


proc odstext; p "Visualise Model Fit on Test Dataset" / style=[color=navy fontsize=16pt just=c];
p "Here we score the Test dataset using DataStep scorecode and visualise the ROC, Lift & Response charts." / style=[color=black fontsize=12pt just=c];
run;

/* visualize lift/ROC stats for model using SGPLOT */
proc sgplot data=WORK._roc_temp noautolegend aspect=1;
	title 'ROC Curve (Target = BAD, Event = 1)';
	xaxis label='False positive rate' values=(0 to 1 by 0.1);
	yaxis label='True positive rate' values=(0 to 1 by 0.1);
	lineparm x=0 y=0 slope=1 / transparency=.7 LINEATTRS=(Pattern=34);
	series x=fpr y=sensitivity;
	inset "AUC=&AUC"/position=bottomright border;
run;

/* Add a row in lift information table for depth of 0.*/
data WORK._extraPoint;
	depth=0;
	CumResp=0;
run;

data WORK._lift_temp;
	set WORK._extraPoint WORK._lift_temp;
run;

proc sgplot data=WORK._lift_temp noautolegend;
	title 'Lift Chart (Target = BAD, Event = 1)';
	xaxis label='Population Percentage';
	yaxis label='Lift';
	series x=depth y=lift;
run;

proc sgplot data=WORK._lift_temp noautolegend;
	title 'Cumulative Lift Chart (Target = BAD, Event = 1)';
	xaxis label='Population Percentage';
	yaxis label='Lift';
	series x=depth y=CumLift;
run;

proc sgplot data=WORK._lift_temp noautolegend aspect=1;
	title 'Cumulative Response Rate (Target = BAD, Event = 1)';
	xaxis label='Population Percentage';
	yaxis label='Response Percentage';
	series x=depth y=CumResp;
	lineparm x=0 y=0 slope=1 / transparency=.7 LINEATTRS=(Pattern=34);
run;

proc delete data=WORK._extraPoint WORK._lift_temp WORK._roc_temp;
run;

/* 6 - Assess Generalizability with k-fold cross validation*/
/* In this section we perform cross validation to assess goodness of fit on our hold-out dataset. */

proc odstext; p "Perform K-Fold Cross Validation"/style=[color=navy fontsize=16pt just=c];
p "Here we define a macro, kFoldCV, which uses the CAS Sampling Actionset to perform k-fold partitioning stratified by BAD. We then score each dataset and append the results to a single table including paritition identifier. Finally, we use PROC ASSESS which runs model assessment by Kfold partition."/style=[color=black fontsize=12pt just=c];
run;

/* we wrap this into a macro called kFoldCV which loads the sampling actions set, performs k-fold CV then scores each partition via DataStep score code.

All results are then unioned into a single table allowing us to use PROC ASSESS for each partition. This creates lift/ROC stats for each partition with the macro returning the results.
*/

%macro kFoldCV(k,data,target,results,scorefile);

/* create k-folds */
ods exclude all;
proc cas;
   loadactionset "sampling";
   action kfold result=r/table={name="&data",groupby={"&target"}}
      k=10  seed=123
      output={casout={name="kfold_out",replace="TRUE"},
              copyvars={"bad","loan","mortdue","value","reason","job","yoj","derog","delinq","clage","ninq","clno","debtinc"},
              foldname='kfold'};
   run;
quit;
ods exclude none;
/* for each k, score and assess fit */
%do i=1 %to &k.;

data score&i.;
set casuser.kfold_out;
where kfold=&&i.;
%include &scorefile;
p_good = 1-p_bad;
if p_good ne . and p_bad ne . then output;
run;

%end;

data casuser.all_scores;
set score1-score&k.;
run;

ods exclude all;
proc assess data=casuser.all_scores nbins=10 ncuts=10;
	target BAD / event="1" level=nominal;
	input P_BAD;
	fitstat pvar=P_GOOD / pevent="0" delimiter=',';
by kfold;
	ods output ROCInfo=&results LIFTInfo=lift_all;
run;
ods exclude none;
%mend;

%let copyvars="'bad','job','reason','loan','value','delinq','derog'";
%let scorefile='<your-path>/score.sas';

/* Run the macro setting K=5 */
%kFoldCV(k=5,data=holdout,target=BAD, results=roc_all, scorefile=&scorefile.);

/* visualize average generalizability */
data cutoff;
set roc_all;
where cutoff=0.5;
run;

proc odstext;p "Visualise Estimated Fit Statistics by Kfold"/style=[color=navy fontsize=16pt just=c];
p "Here we retain only values for the 0.5 cutoff from the ROC and visualise the estimated distributions for KS, Accuracy, F1, AUC, Gini and Misclassification rate from our k-fold partitions."/style=[color=black fontsize=12pt just=c];
/* ods pdf startpage=never; */

proc odstext; p '';run;

ods graphics / height=2in width=2in;

/* here we visualize the range of model assessment measures in a grid plot using ODS GRIDDED layout options. */

ods layout gridded columns= 2 COLUMN_WIDTHS=(2.5in 2.5in) ;

ods region column=1 ;
proc sgplot data=cutoff;
hbox ks2;
title 'Distribution of KS Score';
run;

ods region column=2 ;
proc sgplot data=cutoff;
hbox acc;
title 'Distribution of Accuracy';
run;

ods region column=1 ;
proc sgplot data=cutoff;
hbox f1 ;
title 'Distribution of F1 Score';
run;

ods region column=2 ;
proc sgplot data=cutoff;
hbox c;
title 'Distribution of Area under Curve Score';
run;

ods region column=1 ;
proc sgplot data=cutoff;
hbox gini;
title 'Distribution of Gini';
run;

ods region column=2 ;
proc sgplot data=cutoff;
hbox miscevent;
title 'Distribution of Event Misclassification Rate';
format miscevent percent10.;
run;

ods layout end;

/* ods html5 close; */
 ods pdf close; 