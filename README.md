# MIA_Analysis

## MIA Analysis or the Root cause Analysis: 

Main goal of the analysis is to understand the factors contributing to the device going offline/MIA.

## MIA Root Cause Analysis using Supervised ML Methodology:

* Build cohort with both MIA and Non MIA devices during Jun’20 - Nov’20
* Data cleanup
* Exploratory Data Analysis - checking data distribution b/w feature and label
* Feature engineering - Null values, binning treatment, one hot encoding 
* Run the models for each device type with Wallboards and WRTV high priority
* Build baseline models for performance benchmark with 70/30 split train/test data: Logistic Regression, SVM
* Build advanced models: RF/XGB/Catboost/ADAboost
* GridSearchCV for hyperparameters tuning -- Focus on reducing False Positives
* Test the accuracy of the models on test data 
* Focus on reducing False Positives
* Use LIME framework for feature explainability > Identify high influence features 
* Perform descriptive analysis for the features deemed important

## Cohort Definition:

* Anchor on all Devices having closed MIA cases between Jun’ 20 - Nov’ 20 marking them as 0
* Random sample devices that haven't gone MIA ever based on the device type marking them as 1


The base plan for the analysis can be found in the below linked google doc.

https://docs.google.com/document/d/1cxofRfHKKAbO65cbKVgolOmNgUaTMq25VazYVy4vPpI/edit

## Data Cleanup and Feature Engineering

* Flagging if a device ia a MIA or a Non MIA device
* One hot encoding all categorical variables i.e., software version, SKU, model numbers etc.,
* Bucketing and flagging Free space percentage over the 6 months timeframe
* Removing one of the one-hot encoded categorical columns to avoid dummy variable trap
* Normalizing any numerical variables
* Ensuring each device has only one record 
* Dropping columns with zero or close to zero variance
* Dropping columns having data for only either MIA or Non MIA devices
* Random Sampling ( Up/down sampling) Control cohort (NON MIA devices) data according to the test cohort (MIA Devices) sample size
* Splitting the data into Train/Test/Validation (60/20/20) Cohorts and save the data into .csv files for any further iterations.

## Baseline Modeling

* Removing columns with zero or close to zero variance
* Run k fold cross validation to determine more balanced baseline models
* Create initial models of Logistic, SVM, Decision Tree, Random Forest
* Plot AUC and other metrics i.e., accuracy, confusion matrix
* List out the feature importances of all the features 

## Folder Description

- **Wallboard**: Folder contains all ipynb files and .csv files 
  - **Treasure_Data_Variables**: Folder contains .csv files of activity and wallboard interaction variables created in Treasure data 
  - **JupyterNotebooks**: Folder contains all ipynb files
    - **EDA_Images** : Contains images of MIA and Non-MIA device counts for categorical variables
    - **Wallboard_dataprep.ipynb** : Contains python code for data clean up and feature engin such as one-hot encoding, normalization, train/test/validation split
    - **Baseline Models.ipynb** : Contains python Code for 5 fold cv and hyperparameter tuned models ( Logistic, SVM, Decision Tree, Random Forest ) 
  - **Modeling Results**: Folder contains saved models (.sav files) and feature importances/co efficients  of the models in (.csv files)
