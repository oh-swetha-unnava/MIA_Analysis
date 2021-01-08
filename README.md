# MIA_Analysis

## MIA Analysis or the Root cause Analysis: 

Main goal of the analysis is to understand the factors contributing to the device going offline/MIA.

## MIA Root Cause Analysis using Supervised ML Methodology:

Build cohort with both MIA and Non MIA devices during Jun’20 - Nov’20

Data cleanup

Exploratory Data Analysis - checking data distribution b/w feature and label

Feature engineering - Null values, binning treatment, one hot encoding 

Run the models for each device type with Wallboards and WRTV high priority

Build baseline models for performance benchmark with 70/30 split train/test data: Logistic Regression, SVM

Build advanced models: RF/XGB/Catboost/ADAboost

GridSearchCV for hyperparameters tuning -- Focus on reducing False Positives

Test the accuracy of the models on test data 

Focus on reducing False Positives

Use LIME framework for feature explainability > Identify high influence features 

Perform descriptive analysis for the features deemed important

## Cohort Definition:

Anchor on all Devices having closed MIA cases between Jun’ 20 - Nov’ 20 marking them as 0

Random sample devices that haven't gone MIA ever based on the device type marking them as 1


The base plan for the analysis can be found in the below linked google doc.

https://docs.google.com/document/d/1cxofRfHKKAbO65cbKVgolOmNgUaTMq25VazYVy4vPpI/edit

