---
title: 'Pipengine: an ultra simple YAML-based pipeline execution engine'
tags:
  - pipeline
  - workflows
  - reproducibility
authors:
 - name: Francesco Strozzi
   orcid: 0000-0002-6845-6982
   affiliation: 1
 - name: Raoul Jean Pierre Bonnal
   orcid: 0000-0002-2123-6536
   affiliation: 2
affiliations:
 - name: Enterome Bioscience
   index: 1
 - name: INGM - National Institute of Molecular Genetics
   index: 2
date: 25 July 2017
---

# Summary

This is an ultra simple YAML-based pipeline execution engine. The tool allows defining a pipeline template in YAML, specifing command lines, resources and software to be used along with pipeline steps dependencies. The pipeline can then be applied over a single sample or multiple samples, generating actual runnable bash scripts which can then be sumitted automatically to a scheduling system or runned locally. The bash scripts generated by Pipengine includes error controls and logging for each step, plus the automatical generation of directories based on sample and pipeline steps name, and the moving of input and output data across original and temporary folders if needed. Apart from avoiding the user to rewrite boiler plate code to perform all of these accessory tasks, Pipengine produces a stable and reproducible working and output tree which can be predictably parsed and accessed if other tools and utility to acccess pipelines' intermediate or final results. The software was developed in 2012, so a pre-CWL/WDL era, but has been used across several research groups and core facilities for years.