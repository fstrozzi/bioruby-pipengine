PipEngine
=========

A simple launcher for complex biological pipelines.

PipEngine will generate runnable shell scripts, already configured for the PBS/Torque job scheduler, for each sample in the pipeline. It allows to run a complete pipeline or just a single step or a few steps.

PipEngine is best suited for NGS pipelines, but it can be used for any kind of pipeline that can be runned on a job scheduling system.


:: Topics ::
============

[Usage](https://github.com/bioinformatics-ptp/bioruby-pipengine#-usage-)

[The Pipeline YAML](https://github.com/bioinformatics-ptp/bioruby-pipengine#-the-pipeline-yaml-)

[The Samples YAML](https://github.com/bioinformatics-ptp/bioruby-pipengine#-the-samples-yaml-)

[Input and output conventions](https://github.com/bioinformatics-ptp/bioruby-pipengine#-input-and-output-conventions-)

[Sample groups and complex steps](https://github.com/bioinformatics-ptp/bioruby-pipengine#-sample-groups-and-complex-steps-)

[What happens at run-time](https://github.com/bioinformatics-ptp/bioruby-pipengine#-what-happens-at-run-time-)

[Examples](https://github.com/bioinformatics-ptp/bioruby-pipengine#-examples-)

[PBS Options](https://github.com/bioinformatics-ptp/bioruby-pipengine#-pbs-options-)

:: Usage ::
===========

**Command line**
```shell
pipenengine -p pipeline.yml -f samples.yml -s mapping --local /tmp
```

**Mandatory parameters**
```shell
        --pipeline, -p <s>:   YAML file with pipeline and sample details (default: pipeline.yml)
                  --steps, -s <s+>:   List of steps to be execute
    --samples-file, -f <s>:   YAML file with samples name and directory paths (default: samples.yml)

```
**Optional parameters**
```shell
          --samples, -l <s+>:   List of sample names to run the pipeline
                   --dry, -d:   Dry run. Just create the job script without submitting it to the batch system
             --local, -o <s>:   Local output root folder
   --create-samples, -c <s+>:   Create samples.yml file from a Sample directory (only for CASAVA projects)
           --groups, -g <s+>:   Group of samples to be processed by a given step
              --name, -n <s>:   Analysis name
         --pbs-opts, -b <s+>:   PBS options
         --pbs-queue, -q <s>:   PBS queue
  --inspect-pipeline, -i <s>:   Show pipeline steps
                  --help, -h:   Show this message
```

PipEngine accepts two input files:
* A YAML file describing the pipeline steps
* A YAML file describing samples names, samples location and other samples-specific information


:: The Pipeline YAML ::
=======================

The basic structure of a pipeline YAML is divided into three parts: 1) pipeline name, 2) resources, 3) steps.

An example YAML file is like the following:

```yaml

pipeline: resequencing

resources:
  fastqc: /software/FastQC/fastqc
  bwa: /software/bwa-0.6.2/bwa
  gatk: /software/gatk-lite/GenomeAnalysisTk.jar
  samtools: /software/samtools
  samsort: /software/picard-tools-1.77/SortSam.jar
  mark_dup: /software/picard-tools-1.77/MarkDuplicates.jar
  bam: /software/bam
  pigz: /software/pigz

steps:
  mapping:
    desc: Run BWA on each sample to perform alignment
    run:
     - ls <sample_path>/*_R1_*.gz | xargs zcat | <pigz> -p 10 >> R1.fastq.gz
     - ls <sample_path>/*_R2_*.gz | xargs zcat | <pigz> -p 10 >> R2.fastq.gz
     - <bwa> sampe -P <index> <(<bwa> aln -t 4 -q 20 <index> R1.fastq.gz) <(<bwa> aln -t 4 -q 20 <index> R2.fastq.gz) R1.fastq.gz R2.fastq.gz | <samtools> view -Su - | java -Xmx4g -jar /storage/software/picard-tools-1.77/AddOrReplaceReadGroups.jar I=/dev/stdin O=<sample>.sorted.bam SO=coordinate LB=<pipeline> PL=illumina PU=PU SM=<sample> TMP_DIR=/data/tmp CREATE_INDEX=true MAX_RECORDS_IN_RAM=1000000
     - rm -f R1.fastq.gz R2.fastq.gz
    cpu: 11

  mark_dup:
    run: java -Xmx4g -jar <mark_dup> VERBOSITY=INFO MAX_RECORDS_IN_RAM=500000 VALIDATION_STRINGENCY=SILENT INPUT=<mapping/sample>.sorted.bam OUTPUT=<sample>.md.sort.bam METRICS_FILE=<sample>.metrics REMOVE_DUPLICATES=false

  realign_target:
    run: java -Xmx4g -jar <gatk> -T RealignerTargetCreator -I <mark_dup/sample>.md.sort.bam -nt 8 -R <genome> -o <sample>.indels.intervals
    cpu: 8

  realign:
    run: java -Xmx4g -jar <gatk> -T IndelRealigner -LOD 0.4 -model USE_READS --disable_bam_indexing --target_intervals <realign_target/sample>.indels.intervals -R <genome> -I <mark_dup/sample>.md.sort.bam -o <sample>.realigned.bam

  fixtags:
    run: <samtools> calmd -r -E -u <realign/sample>.realigned.bam <genome> | <bam> squeeze --in -.ubam --out <sample>.final.bam --rmTags 'XM:i;XG:i;XO:i' --keepDups

  bam_index:
    run: <samtools> index <fixtags/sample>.final.bam

  clean:
    run: ls | grep -v final | xargs rm -fr

```

Resources definition
--------------------

PipEngine is entirely based on the placeholder and substitution logic. For example in the Pipeline YAML, each tool is declared under the resources and at run time PipEngine will search for the corresponding placeholder in the command lines.

So, for instance, if I have declared a software **bwa** under resources, PipEngine will search for a ```<bwa>``` placeholder in all the command lines and will substitute it with the software complete path declared in resources.

This makes command lines definition shorter and easier to read and avoid problems when moving from one software version to another (i.e. you just need to change the bwa definition once, and not 10 times in 5 different command lines)

The same thing happens for samples names, input and output directories and intermediate output files. This allows to create true pipelines templates that can be reused and applied to different samples sets.

Step definition
---------------

The step must be defined using standard keys:

* the first key must be the step name
* under the step name, a **run** key must be defined to hold the actual command line that will be executed
* a **cpu** key must be defined if the command line uses more than 1 CPU at runtime
* a **group** key must be defined if the command line takes as input more than one sample (more details later)
* a **desc** key has been added to insert a short description that will be displayed using the **-i** option of PipEngine

A note on the **run** key. If a single step need more than a command line to execute the required actions, these multiple command lines must be defined as an array in YAML (see the mapping step in the above example).


:: The Samples YAML ::
=====================

The samples YAML is much simpler then the pipeline YAML:

```yaml
resources:
  index: /storage/genomes/bwa_index/genome
  genome: /storage/genomes/genome.fa
  output: /storage/results

samples:
  sampleA: /ngs_reads/sampleA
  sampleB: /ngs_reads/sampleB
  sampleC: /ngs_reads/sampleC
  sampleD: /ngs_reads/sampleD
```

In this YAML there is again a **resources** key, but this time the tags defined here are dependent on the samples described in the YAML.

For instance, if I am working with human RNA-seq samples, these data must be aligned on the human genome, so it makes sense that the **genome** tag must be defined here and not in the pipeline YAML, which must be as much generic as possible.

Mainly the tags defined under the samples **resources** are dependent on the pipeline one wants to run. So if using BWA to perform reads alignemnt, an **index** tag must be defined here to set the BWA index prefix and it will be substituted in the pipelines command lines every time an ```<index>``` placeholder will be found in the pipeline YAML.

:: Input and output conventions ::
==================================

The input file in the pipeline YAML are defined by the ```<sample>``` placeholder that will be substituted with the sample name while the ```<sample_path>``` will be changed with the location where initial sample data (i.e. raw sequencing reads) are stored. Both this information are coming from the sample YAML file.

The ```<output>``` placeholder is a generic one to define the root location for the pipeline outputs. This parameter is also defined in the samples YAML.

By convention, each sample output is saved under a folder with the sample name and each step is saved in a sub-folder with the step name.

That is, given a generic /storage/pipeline_results ```<output>``` folder, the outputs of the **mapping** step will be organized in this way:

```shell
/storage/pipeline_results/SampleA/mapping/SampleA.bam
                         /SampleB/mapping/SampleB.bam
                         /SampleC/mapping/SampleC.bam
                         /SampleD/mapping/SampleD.bam
```

This simple convention keeps things clearer and well organized. The output file name can be decided during the pipeline creation, but it's a good habit to name it using the sample name.

When new steps of the same pipeline are run output folders are updated accordingly, so for example if after the **mapping** step a **mark_dup** step is run, the output folder will look like this:

```shell
/storage/pipeline_results/SampleA/mapping
                         /SampleA/mark_dup

/storage/pipeline_results/SampleB/mapping
                         /SampleB/mark_dup
                  .....
```


How steps are connected together
--------------------------------

One step is connected to another by simply requiring that its input is coming from the output of another step. This is just achived by a combination of ```<output>``` and ```<sample>``` placeholders in the pipeline command line definitions.

For instance, if I have a resequencing pipeline that will first run BWA to map the reads and then a mark duplicate step, the mark_dup step will be dependent from the BWA output.

```yaml
  mapping:
    run:
     - ls <sample_path>/*_R1_*.gz | xargs zcat | <pigz> -p 10 >> R1.fastq.gz
     - ls <sample_path>/*_R2_*.gz | xargs zcat | <pigz> -p 10 >> R2.fastq.gz
     - <bwa> sampe -P <index> <(<bwa> aln -t 4 -q 20 <index> R1.fastq.gz) <(<bwa> aln -t 4 -q 20 <index> R2.fastq.gz) R1.fastq.gz R2.fastq.gz > <sample>.sorted.bam
     - rm -f R1.fastq.gz R2.fastq.gz
    cpu: 11

  mark_dup:
    run: java -Xmx4g -jar <mark_dup> INPUT=<mapping/sample>.sorted.bam OUTPUT=<sample>.md.sort.bam
```

So in the **mark_dup** step the input placeholder (defined under the **run** key in the pipeline YAML) will be written as:

```
<mapping/sample>.sorted.bam
```

If the ```<output>``` tag is defined for instance as "/storage/results", this will be translated at run-time into:

```
/storage/results/SampleA/mapping/SampleA.sorted.bam
```

for SampleA outputs. Basically the ```<mapping/sample>``` placeholder is a shortcut for ```<output>/<sample>/{step name, mapping in this case}/<sample>```

Following the same idea, using a ```<mapping/>``` placeholder (note the / at the end) will be translated into ```<output>/<sample>/{step name, mapping in this case}/``` , covering the case when one wants to point to the previous step output directory, but without having the ```<sample>``` appended to the end of the path.

More complex dependences can be defined by combinations of ```<output>``` and ```<sample>``` placeholders, or using the ```<step/>``` and ```<step/sample>``` placeholders, without having to worry about the actual sample name and the complete input and output paths.


:: Sample groups and complex steps ::
=====================================

The pipline steps can be defined to run on a single sample or to take as input more than one sample data, depending on the command line used.

A typical example is running a differential expression step for example with CuffDiff. This requires to take all the output generated from the previous Cufflinks step (i.e. the gtf files) and process them to generate a unique transcripts reference (CuffCompare) and then perform the differential expression across the samples using the BAM files generated by, let's say, TopHat in a **mapping** step.

This is an extract of the step definition in the pipeline YAML to describe these two steps:

```yaml
  diffexp:
    groups:
      - <output>/<sample>/cufflinks/transcripts.gtf
      - <mapping/sample>_tophat/accepted_hits.bam
    run:
      - echo '<groups1>' | sed -e 's/,/ /g' | xargs ls >> gtf_list.txt
      - <cuffcompare> -s <genome> -r <gtf> -i gtf_list.txt
      - <cuffdiff> -p 12 -N -u -b <genome> ./*combined.gtf <groups2>
    cpu: 12
```

In this case we need to combine the outputs of all the samples from the cufflinks step and pass that information to cuffcompare and combine the outputs of the mapping steps and pass them to the cuffdiff command line.

This is achived in two ways. First, the step definition must include a **groups** key, that simply defines what, for each sample, will be substituted where the ```<groups>``` placeholder is found.

In the example above, the step includes two command lines, one for cuffcompare and the other for cuffdiff. Cuffcompare requires the transcripts.gtf for each sample, while Cuffdiff requires the BAM file for each sample, plus the output of Cuffcompare.

So the two command lines need two different outputs from the same set of samples, therefore two **groups** keywords are defined as well as two placeholders ```<groups1>``` and ```<groups2>```

Once the step has been defined in the pipeline YAML, pipengine must be invoked using the **-g** parameter, to specify the samples that should be grouped together by this step:

```shell
pipengine -p pipeline.yml -g SampleA,SampleB SampleC,SampleB
```

Note that the use of commas is not casual, since the **-g** parameter takes the sample names and underneath it will combine the sample name, with the 'groups' keywords and then it will substitute back the command line by keeping the samples in the same order as provided with the **-g**.

The above command line will be translated, for the **cuffdiff** command line in the following:

```shell
/software/cuffdiff -p 12 -N -u -b /storage/genome.fa combined.gtf /storage/results/SampleA/cufflinks/transcripts.gtf,/storage/results/SampleB/cufflinks/transcripts.gtf /storage/results/SampleC/cufflinks/transcripts.gtf /storage/results/SampleD/cufflinks/transcripts.gtf
```

and this will correspond to the way CuffDiff wants biological replicates for each condition to be described on the command line.

**Note**

Sample groups management is complex and it's a task that can't be easily generalized since every tool as it's own way to put and organize the inputs on the command line. This approach it's not the best but works quite well, even if there are some drawbacks. For instance, as stated above, the samples groups is processed and passed to command lines as it is taken from the **-g** parameter.

So for Cuffdiff, the presence of commas is critical to divide biological replicates from different conditions, but for Cuffcompare the commas are not needed and will raise an error on the command line. That's the reason of the:

```shell
echo '<groups1>' | sed -e 's/,/ /g' | xargs ls >> gtf_list.txt
```

This line generates the input file for Cuffcompare with the list of the transcripts.gtf files for each sample, generated using the 'groups' definition in the pipeline YAML and the line passed through the **-g** parameter, but getting rid of the commas that separate sample names. It's a workaround and it's not a super clean solution, but PipEngine wants to be a general tool not binded to specific corner cases and it always lets the user define it's own custom command lines to manage particular steps, as in this case.


:: What happens at run-time ::
==============================

When invoking PipEngine, the tool will look for the pipeline YAML specified and for the sample YAML file. It will load the list of samples (names and paths of input data) and for each sample it will load the information of the step specified in the command line ( **-s** parameter ).

PipEngine will then combine the data from the two YAML, generating the specific command lines of the selected steps and substituing all the placeholders to generate the final command lines.

A shell script will be finally generated, for each sample, that will contain all the instructions to run a specific step of the pipeline plus the meta-data for the PBS scheduler.

If not invoked with the **-d** option (dry-run) PipEngine will directly submit the jobs to the PBS scheduler using the "qsub" command.

Dry Run
-------

The **-d** parameter lets you create the runnable shell scripts without submitting them to PBS. Use it often to check that the pipeline that will be executed is correct and it is doing what you thought.

Use it also to learn how the placeholders works, especially the dependency placeholders (e.g. ```<mapping/sample>```) and to cross-check that all the placeholders in the pipeline command lines were substituted correctly before submitting the jobs.

Local output folder
-------------------

By using the '--local' option, PipEngine will generate a job script (for each sample) that will save all the output files or folders for a particular step in a local directory (e.g. /tmp).

By default PipEngine will generate output folders directly under the location defined by the ```<ouput>``` tag in the Sample YAML. The local solution instead can be useful when we don't want to save directly to the final location (e.g a slow network storage) or we don't want to keep all the intermediate files but just the final ones.

With this option enabled, PipEngine will also generate instructions in the job script to copy, at the end of the job, the final output folder from the local temporary directory to the final output folder (i.e. ```<output>```) and then to remove the local copy.

When '--local' is used a UUID is generated for each job and prepended to the job name and to the local output folder, to avoid possible name collisions and data overwrite if more jobs with the same name (e.g. mapping) are running at the same time, writing on the same temporary location.

One job with multiple steps
---------------------------

It is of course possible to aggregate multiple steps of a pipeline and run them in one single job. For instance let's say I want to run in the same job the steps mapping, mark_dup and realign_target (see pipeline YAML example above).

From the command line it's just:

```shell
pipengine -p pipeline.yml -s mapping mark_dup realign_target
```

A single job script, for each sample, will be generated with all the instructions for these steps. If more than one step declares a **cpu** key, the highest cpu value will be assigned for the whole job.

If the pipeline is defined with steps that are dependent one from the other, in the scenario where more steps are run together PipEngine will check if for a given step the expected input is already available. If not, it will assume the input will be found in the current working directory, because the input itself has not yet been generated.

This is because the output folders are by definition based on the job executed. So one step in one job, means one output folder with the step name, but more steps in one job means that all the outputs generated will be in the same job directory that will be named by default as the concatenation of all the steps names.

Since this can be a problem when a lot of steps are run together in the same job, a '--name' parameter it's available to rename the job (and thus the corresponding output folder).

:: Examples ::
==============

Example 1: One step and multiple command lines
----------------------------------------------

This is an example on how to prepare the inputs for BWA and run it along with Samtools:

**pipeline.yml**
```yaml
pipeline: resequencing

resources:
  bwa: /software/bwa-0.6.2/bwa
  samtools: /software/samtools

steps:
  mapping:
    run:
     - ls <sample_path>/*_R1_*.gz | xargs zcat | <pigz> -p 10 >> R1.fastq.gz
     - ls <sample_path>/*_R2_*.gz | xargs zcat | <pigz> -p 10 >> R2.fastq.gz
     - <bwa> sampe -P <index> <(<bwa> aln -t 4 -q 20 <index> R1.fastq.gz) <(<bwa> aln -t 4 -q 20 <index> R2.fastq.gz) R1.fastq.gz R2.fastq.gz | <samtools> view -Sb - > <sample>.bam
     - rm -f R1.fastq.gz R2.fastq.gz
    cpu: 11
```

**samples.yml**
```yaml
resources:
  index: /storage/genomes/bwa_index/genome
  genome: /storage/genomes/genome.fa
  output: /storage/results

samples:
  sampleA: /ngs_reads/sampleA
  sampleB: /ngs_reads/sampleB
  sampleC: /ngs_reads/sampleC
  sampleD: /ngs_reads/sampleD
```

Running PipEngine with the following command line:

```
pipengine -p pipeline.yml -f samples.yml -s mapping
```

will generate a runnable shell script for each sample:

```shell
#!/bin/bash
#PBS -N 37735f50-mapping
#PBS -l ncpus=11

mkdir -p /storage/results/sampleA/mapping
cd /storage/results/sampleA/mapping
ls /ngs_reads/sampleA/*_R1_*.gz | xargs zcat | pigz -p 10 >> R1.fastq.gz
ls /ngs_reads/sampleA/*_R2_*.gz | xargs zcat | pigz -p 10 >> R2.fastq.gz
/software/bwa-0.6.2/bwa sampe -P /genomes/bwa_index/genome <(/software/bwa-0.6.2/bwa aln -t 4 -q 20 /genomes/bwa_index/genome R1.fastq.gz) <(/software/bwa-0.6.2/bwa aln -t 4 -q 20 /genomes/bwa_index/genome R2.fastq.gz) R1.fastq.gz R2.fastq.gz | /software/samtools view -Sb - > sampleA.bam
rm -f R1.fastq.gz R2.fastq.gz
```
As you can see the command line described in the pipeline YAML are translated into normal Unix command lines, therefore every solution that works on a standard Unix shell (pipes, bash substitutions) is perfectly acceptable.

In this case also, the **run** key defines three different command lines, that are described using YAML array (a line prepended with a -). This command lines are all part of the same step, since the first two are required to prepare the input for the third command line (BWA), using standard bash commands.

As a rule of thumb you should put more command line into an array under the same step if these are all logically correlated and required to manipulate intermidiate files. Otherwise if command lines executes conceptually different actions they should go into different steps.

Example 2: Multiple steps in one job
------------------------------------

Now I want to execute more steps in a single job for each sample. The pipeline YAML is defined in this way:

```yaml

pipeline: resequencing

resources:
  bwa: /software/bwa-0.6.2/bwa
  samtools: /software/samtools
  mark_dup: /software/picard-tools-1.77/MarkDuplicates.jar
  gatk: /software/GenomeAnalysisTK/GenomeAnalysisTK.jar

steps:
  mapping:
    run:
     - ls <sample_path>/*_R1_*.gz | xargs zcat | pigz -p 10 >> R1.fastq.gz
     - ls <sample_path>/*_R2_*.gz | xargs zcat | pigz -p 10 >> R2.fastq.gz
     - <bwa> sampe -P <index> <(<bwa> aln -t 4 -q 20 <index> R1.fastq.gz) <(<bwa> aln -t 4 -q 20 <index> R2.fastq.gz) R1.fastq.gz R2.fastq.gz | <samtools> view -Su - | java -Xmx4g -jar /storage/software/picard-tools-1.77/AddOrReplaceReadGroups.jar I=/dev/stdin O=<sample>.sorted.bam SO=coordinate LB=<pipeline> PL=illumina PU=PU SM=<sample> TMP_DIR=/data/tmp CREATE_INDEX=true MAX_RECORDS_IN_RAM=1000000
     - rm -f R1.fastq.gz R2.fastq.gz
    cpu: 11

  mark_dup:
    run: java -Xmx4g -jar <mark_dup> VERBOSITY=INFO MAX_RECORDS_IN_RAM=500000 VALIDATION_STRINGENCY=SILENT INPUT=<mapping/sample>.sorted.bam OUTPUT=<sample>.md.sort.bam METRICS_FILE=<sample>.metrics REMOVE_DUPLICATES=false

  realign_target:
    run: java -Xmx4g -jar <gatk> -T RealignerTargetCreator -I <mark_dup/sample>.md.sort.bam -nt 8 -R <genome> -o <sample>.indels.intervals
    cpu: 8
```

The sample YAML file is the same as the example above. Now to execute together the 3 steps defined in the pipeline, PipEngine must be invoked with this command line:

```
pipengine -p pipeline.yml  -f samples.yml -s mapping mark_dup realign_target
```

When running this command line, PipEngine will raise a warning:

```shell
Warning: Directory /storage/results/sampleA/mapping not found. Assuming input will be in the CWD
```

this is normal as described in [One job with multiple steps](https://github.com/bioinformatics-ptp/bioruby-pipengine#one-job-with-multiple-steps) since the second and third steps did not find the output of the first step, as it has not yet been executed.

And this will be translated into the following shell script (one for each sample):

```shell
#!/bin/bash
#PBS -N ff020300-mapping-mark_dup-realign_target
#PBS -l ncpus=11

mkdir -p /storage/results/sampleB/mapping-mark_dup-realign_target
cd /storage/results/sampleB/mapping-mark_dup-realign_target
ls /ngs_reads/sampleB/*_R1_*.gz | xargs zcat | pigz -p 10 >> R1.fastq.gz
ls /ngs_reads/sampleB/*_R2_*.gz | xargs zcat | pigz -p 10 >> R2.fastq.gz
/software/bwa-0.6.2/bwa sampe -P /storage/genomes/bwa_index/genome <(/software/bwa-0.6.2/bwa aln -t 4 -q 20 /genomes/bwa_index/genome R1.fastq.gz) <(/software/bwa-0.6.2/bwa aln -t 4 -q 20 /genomes/bwa_index/genome R2.fastq.gz) R1.fastq.gz R2.fastq.gz | /software/samtools view -Sb - > sampleA.bam
rm -f R1.fastq.gz R2.fastq.gz
java -Xmx4g -jar /software/picard-tools-1.77/MarkDuplicates.jar VERBOSITY=INFO MAX_RECORDS_IN_RAM=500000 VALIDATION_STRINGENCY=SILENT INPUT=sampleB.sorted.bam OUTPUT=sampleB.md.sort.bam METRICS_FILE=sampleB.metrics REMOVE_DUPLICATES=false
java -Xmx4g -jar /software/GenomeAnalysisTk/GenomeAnalysisTk.jar -T RealignerTargetCreator -I sampleB.md.sort.bam -nt 8 -R /storage/genomes/genome.fa -o sampleB.indels.intervals
```

:: PBS Options ::
=================

If there is the need to pass to PipEngine specific PBS options, the ```--pbs-opts``` parameter can be used.

This parameter accepts a list of options and each one will be added to the PBS header in the shell script, along with the ```-l``` PBS parameter.

So for example, the following options passed to ```--pbs-opts```:

```shell
--pbs-opts nodes=2:ppn=8 host=node5
```

will become, in the shell script:

```shell
#PBS -l nodes=2:ppn=8
#PBS -l host=node5
```

If a specific queue need to be selected for sending the jobs to PBS, the ```--pbs-queue``` parameter can be used. This will pass to the ```qsub``` command the ```-q <queue name>``` taken from the command line.

Copyright
=========

(c)2013 Francesco Strozzi
