PipEngine
=========

A simple launcher for complex biological pipelines.

PipEngine will generate runnable shell scripts, already configured for the PBS/Torque job scheduler, for each sample in the pipeline. It allows to run a complete pipeline or just a single step depending on the needs.

PipEngine is best suited for NGS pipelines, but it can be used for any kind of pipeline that can be runned on a job scheduling system and which is "sample" centric, i.e. you have from one side a list of samples with their corresponding raw data, and from the other side a pipeline that you would like to apply to them.

PipEngine was developed to combine the typical flexibility and portability of shell scripts, with the concept of pipeline templates that can be easily applied on different input data to reproduce scientific results. The overall improvement over Makefiles or customised ad-hoc shell scripts is better readability of the pipelines using the YAML format, especially for people with no coding experience, the automated scripts generation which allows adding extra functionalities like error controls and logging directly into script jobs, and an enforced separation between the description of input data and the pipeline template, which improves clarity and reusability of analysis protocols.


Installation
============

If you already have Ruby, just install PipEngine using RubyGems:

```shell
gem install bio-pipengine
```

If you don't have Ruby installed we reccomend you use the Anaconda Package Manager.

Download the installer from [here](http://conda.pydata.org/miniconda.html) and once installed you can simply type:

```shell
conda install -c bioconda ruby
```

and then install PipEngine using RubyGems:

```shell
gem install bio-pipengine
```

Pipengine has been tested and should work with Ruby >= 2.1.2

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

[Extending and contributing](https://github.com/bioinformatics-ptp/bioruby-pipengine#-extending-and-contributing-)

:: Usage ::
===========


```shell
> pipengine -h
List of available commands:
	run		Submit pipelines to the job scheduler
```

Command line for RUN mode
-------------------------

**Command line**
```shell
> pipengine run -p pipeline.yml -f samples.yml -s mapping --tmp /tmp
```

**Parameters**
```shell
  -p, --pipeline=<s>            YAML file with pipeline and sample details (default: pipeline.yml)
  -f, --samples-file=<s>        YAML file with samples name and directory paths (default: samples.yml)
  -l, --samples=<s+>            List of sample names to run the pipeline
  -s, --steps=<s+>              List of steps to be executed
  -d, --dry                     Dry run. Just create the job script without submitting it to the batch system
  -t, --tmp=<s>                 Temporary output folder
  -c, --create-samples=<s+>     Create samples.yml file from a Sample directory (only for CASAVA projects)
  -m, --multi=<s+>              List of samples to be processed by a given step (the order matters)
  -g, --group=<s>               Specify the group of samples to run the pipeline steps on (do not specify --multi)
  -a, --allgroups               Apply the step(s) to all the groups defined into the samples file
  -n, --name=<s>                Analysis name
  -o, --output-dir=<s>          Output directory (override standard output directory names)
  -b, --pbs-opts=<s+>           PBS options
  -q, --pbs-queue=<s>           PBS queue
  -i, --inspect-pipeline=<s>    Show steps
  --log=<s>                     Log script activities, by default stdin. Options are fluentd (default: stdin)
  -e, --log-adapter=<s>         (stdin|syslog|fluentd) In case of fluentd use http://destination.hostname:port/yourtag
  --tag=<s+>                    Overwrite tags present in samples.yml and pipeline.yml files (e.g. tag1=value1 tag2=value2)
  -h, --help                    Show this message
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
  bwa: /software/bwa
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

A step must be defined using standard keys:

* the first key must be the step name
* under the step name, a **run** key must be defined to hold the actual command line that will be executed
* a **cpu** key must be defined if the command line uses more than 1 CPU at runtime
* a **multi** key must be defined if the command line takes as input more than one sample (more details later)
* a **desc** key has been added to insert a short description that will be displayed using the **-i** option of PipEngine
* a **nodes** and **mem** keys can be used to specify the resources needed for this job

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

Generally, the tags defined under the samples **resources** are dependent on the pipeline and analysis one wants to run. So if using BWA to perform reads alignemnt, an **index** tag must be defined here to set the BWA index prefix and it will be substituted in the pipelines command lines every time an ```<index>``` placeholder will be found in the pipeline YAML.

Sample groups
-------------

If you want to organize your samples by groups, it is possible to do it directly in the samples.yml file:


```yaml
resources:
  index: /storage/genomes/bwa_index/genome
  genome: /storage/genomes/genome.fa
  output: /storage/results

samples:
  Group1:
    sampleA: /ngs_reads/sampleA
    sampleB: /ngs_reads/sampleB
  Group2:
    sampleC: /ngs_reads/sampleC
    sampleD: /ngs_reads/sampleD
```

Then, by using the **-g** option of PipEngine, it is possible to run steps and pipelines directly on groups of samples.


How to create the Samples file
------------------------------

PipEngine is created to work primarly for NGS pipelines and with Illumina data in mind. So, the easiest thing to do if you have your samples already organized into a typical Illumina folder is to run:

```shell
> pipengine run -c /path/to/illumina/data
```

This will generate a samples.yml file with all the sample names and path derived from the run folder. The "resources" part is left blank for you to fill.

As a plus, if you have your samples scattered thoughout many different run folders, you can specify all the paths that you want to PipEngine and it will combine all the paths in the same samples file. So if you have your samples spread across let's say 3 runs, you can call PipEngine in this way:

```shell
> pipengine run -c /path/to/illumina/run1 /path/to/illumina/run2 /path/to/illumina/run3
```

If a sample is repeated in more than one run, all the paths will be combined in the samples.yml and PipEngine will take care of handling the multiple paths correctly.



:: Input and output conventions ::
==================================

The inputs in the steps defined in the pipeline YAML are expressed by the ```<sample>``` placeholder that will be substituted with a sample name and the ```<sample_path>```, which will be changed with the location where initial data (i.e. raw sequencing reads) are stored for that particular sample. Both this information are provided in the sample YAML file.

The ```<output>``` placeholder is a generic one to define the root location for the pipeline outputs. This parameter is also defined in the samples YAML. By default, PipEngine will write jobs scripts and will save stdout and stderr files from PBS in this folder. 

By convention, each sample output is saved under a folder with the sample name and each step is saved in a sub-folder with the step name.

That is, given a generic /storage/pipeline_results ```<output>``` folder, the outputs of the **mapping** step will be organized in this way:

```shell
/storage/pipeline_results/SampleA/mapping/SampleA.bam
                         /SampleB/mapping/SampleB.bam
                         /SampleC/mapping/SampleC.bam
                         /SampleD/mapping/SampleD.bam
```

This simple convention keeps things clean and organized. The output file name can be decided during the pipeline creation, but it's a good habit to name it using the sample name.

When new steps of the same pipeline are run, output folders are updated accordingly. So for example if after the **mapping** step a **mark_dup** step is run, the output folder will look like this:

```shell
/storage/pipeline_results/SampleA/mapping
                         /SampleA/mark_dup

/storage/pipeline_results/SampleB/mapping
                         /SampleB/mark_dup
                  .....
```

In case you are working with group of samples, specified by the **-g** option, the output folder will be changed to reflect the samples grouping. So for example if a **mapping** step is called on the **Group1** group of samples, all the outputs will be saved under the ```<output>/Group1``` folder and results of mapping for SampleA, will be found under ```<output>/Group1/SampleA/mapping``` .


How steps are connected together
--------------------------------

One step is connected to another by simply requiring that its input is the output of another preceding step. This is just achived by a combination of ```<output>``` and ```<sample>``` placeholders in the pipeline command line definitions.

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

Following the same idea, using a ```<mapping/>``` placeholder (note the / at the end) will be translated into ```<output>/<sample>/{step name, mapping in this case}/``` , to address the scenario when a user wants to point to the previous step output directory, but without having the ```<sample>``` appended to the end of the path.

More complex dependences can be defined by combinations of ```<output>``` and ```<sample>``` placeholders, or using the ```<step/>``` and ```<step/sample>``` placeholders, without having to worry about the actual sample name and the complete input and output paths.

Jobs dependencies
-------------------------
Steps can also be defined with dependencies so the user can just call the final step and all the upper chain is called automatically. To achieve this task Pipengine requires that the user defines a
```
 pre:
```
tag in the step definition:

```
  root_step:
    desc: root step to test dependencies
    run:
     - echo "root"

  child_step:
    desc: child step to test dependencies
    pre: root_step
    run:
      - echo "I am the child"
```


:: Multi-Samples and complex steps ::
=====================================

The pipeline steps can be defined to run on a single sample or to take as input more than one sample data, depending on the command line used.

A typical example is running a differential expression step for example with CuffDiff. This requires to take all the output generated from the previous Cufflinks step (i.e. the gtf files) and process them to generate a unique transcripts reference (CuffCompare) and then perform the differential expression across the samples using the BAM files generated by, let's say, TopHat in a **mapping** step.

This is an extract of the step definition in the pipeline YAML to describe these two steps:

```yaml
  diffexp:
    multi:
      - <output>/<sample>/cufflinks/transcripts.gtf
      - <mapping/sample>_tophat/accepted_hits.bam
    run:
      - echo '<multi1>' | sed -e 's/,/ /g' | xargs ls >> gtf_list.txt
      - <cuffcompare> -s <genome> -r <gtf> -i gtf_list.txt
      - <cuffdiff> -p 12 -N -u -b <genome> ./*combined.gtf <multi2>
    cpu: 12
```

In this case we need to combine the outputs of all the samples from the cufflinks step and pass that information to cuffcompare and combine the outputs of the mapping steps and pass them to the cuffdiff command line.

This is achived in two ways. First, the step definition must include a **multi** key, that simply defines what, for each sample, will be substituted where the ```<multi>``` placeholder is found.

In the example above, the step includes two command lines, one for cuffcompare and the other for cuffdiff. Cuffcompare requires the transcripts.gtf for each sample, while Cuffdiff requires the BAM file for each sample, plus the output of Cuffcompare.

So the two command lines need two different kind of files as input from the same set of samples, therefore two **multi** keywords are defined as well as two placeholders ```<multi1>``` and ```<multi2>```

Once the step has been defined in the pipeline YAML, PipEngine must be invoked using the **-m** parameter, to specify the samples that should be grouped together by this step:

```shell
pipengine run -p pipeline.yml -m SampleA,SampleB SampleC,SampleB
```

Note that the use of commas is not casual, since the **-m** parameter specifies not only which samples should be used for this step, but also how they should be organized on the corresponding command line. The **-m** parameter takes the sample names and underneath it will combine the sample name with the 'multi' keywords and then it will substitute back the command line by keeping the samples in the same order as provided with the **-m**.

The above command line will be translated, for the **cuffdiff** command line in the following:

```shell
/software/cuffdiff -p 12 -N -u -b /storage/genome.fa combined.gtf /storage/results/SampleA/cufflinks/transcripts.gtf,/storage/results/SampleB/cufflinks/transcripts.gtf /storage/results/SampleC/cufflinks/transcripts.gtf /storage/results/SampleD/cufflinks/transcripts.gtf
```

and this will correspond to the way CuffDiff wants biological replicates for each condition to be described on the command line.

**Note**

Multi-samples step management is complex and it's a task that can't be easily generalized since every software has it's own way to require and organize the inputs on the command line. This approach it's probably not the most elegant solution but works quite well, even if there are some drawbacks. For instance, as stated above, the samples groups is processed and passed to command lines as it is taken from the **-m** parameter.

So for Cuffdiff, the presence of commas is critical to divide biological replicates from different conditions, but for Cuffcompare the commas are not needed and will raise an error on the command line. That's the reason of the:

```shell
echo '<multi1>' | sed -e 's/,/ /g' | xargs ls >> gtf_list.txt
```

This line generates the input file for Cuffcompare with the list of the transcripts.gtf files for each sample, generated using the 'multi' definition in the pipeline YAML and the line passed through the **-m** parameter, but getting rid of the commas that separate sample names. It's a workaround and it's not a super clean solution, but PipEngine wants to be a general tool not binded to specific corner cases and it always lets the user define it's own custom command lines to manage particular steps, as in this case.

Composable & Modular steps definition
------------------------------------

Since now steps are defined inside a single YAML file. This approach is usefult to have a stable and reproducible analysis pipeline. But what if, multiple users whant to collaborate on the same pipeline improving it and, most importantly, re-using the same steps in different analyses ? What happend is a proliferation of highly similar pipelines that are very complicate to compare and to maintain over time.
In this scenario, the very first thing that a developer imagine is the ability to include external files, unfortunately YAML does not implement this feature. A possible workaround, remember that we are in the Ruby land, is to embed some Ruby code into the YAML file and include external steps.

Creating a file `mapping.yml` that describe the mapping step with BWA

```
mapping:
  cpu: 8
  desc: Run BWA MEM and generates a sorted BAM file
  run:
   - <bwa> mem -t <cpu> -R '@RG\tID:<flowcell>\tLB:<sample>\tPL:ILLUMINA\tPU:<flowcell>\tCN:PTP\tSM:<sample>' <index> <trim/sample>.trim.fastq | <samtools> view -bS - > <sample>.bam
   - <samtools> sort -@ <cpu> <sample>.bam <sample>.sort
   - rm -f <sample>.bam
```

is then possible to include the `mapping.yml` file inside your pipeline with a snipped of Ruby code `<%= include :name_of_the_step, "file_step.yml" %>
Right now is very important that you place the tag at the very first start of the line ( no spaces at the beginning of the line)

```
steps:
<%= include :mapping, "./mapping.yml" %>

  index:
    desc: Make BAM index
    run: <samtools> index <mapping/sample>.sort.bam
````

are later run pipengine as usual.
TODO: Dump the whole pipeline file for reproducibility purposes.


:: What happens at run-time ::
==============================

When invoking PipEngine, the tool will look for the pipeline YAML specified and for the sample YAML file. It will load the list of samples (names and paths of input data) and for each sample it will load the information of the step specified in the command line ( **-s** parameter ).

PipEngine will then combine the data from the two YAML, generating the specific command lines of the selected steps and substituing all the placeholders to generate the final command lines.

A shell script will be finally generated, for each sample, that will contain all the instructions to run a specific step of the pipeline plus the meta-data for the PBS scheduler. The shell scripts are written inside the directory specified on the ```output:``` key in the ```samples.yml``` file, the directory is created if it does not exist.

If not invoked with the **-d** option (dry-run) PipEngine will directly submit the jobs to the PBS scheduler using the "qsub" command.

Dry Run
-------

The **-d** parameter lets you create the runnable shell scripts without submitting them to PBS. Use it often to check that the pipeline that will be executed is correct and it is doing what you thought. The runnable scripts are saved by default in the ```<output>``` directory.

Use it also to learn how the placeholders works, especially the dependency placeholders (e.g. ```<mapping/sample>```) and to cross-check that all the placeholders in the pipeline command lines were substituted correctly before submitting the jobs.

Temporary output folder
-------------------

By using the '--tmp' option, PipEngine will generate a job script (for each sample) that will save all the output files or folders for a particular step in a directory (e.g. /tmp) that is different from the one provided with the ```<output>```.

By default PipEngine will generate output folders directly under the location defined by the ```<ouput>``` tag in the Sample YAML. The --tmp solution instead can be useful when we don't want to save directly to the final location (e.g maybe a slower network storage) or we don't want to keep all the intermediate files but just the final ones.

With this option enabled, PipEngine will also generate instructions in the job script to copy, at the end of the job, all the outputs from the temporary directory to the final output folder (i.e. ```<output>```) and then to remove the temporary copy.

When '--tmp' is used, a UUID is generated for each job and prepended to the job name and to the temporary output folder, to avoid possible name collisions and data overwrite if more jobs with the same name (e.g. mapping) are running and writing to the same temporary location.

One job with multiple steps
---------------------------

It is of course possible to aggregate multiple steps of a pipeline and run them in one single job. For instance let's say I want to run in the same job the steps mapping, mark_dup and realign_target (see pipeline YAML example above).

From the command line it's just:

```shell
pipengine run -p pipeline.yml -s mapping mark_dup realign_target
```

A single job script, for each sample, will be generated with all the instructions for these steps. If more than one step declares a **cpu** key, the highest cpu value will be assigned for the whole job.

Each step will save outputs into a separated folder, under the ```<output>```, exactly if they were run separately. This way, if the job fails for some reason, it will be possible to check which steps were already completed and restart from there.

When multiple steps are run in the same job, by default PipEngine will generate the job name as the concatenation of all the steps names. Since this could be a problem when a lot of steps are run together in the same job, a '--name' parameter it's available to rename the job in a more convenient way.

:: Examples ::
==============

All these files can be found into the test/examples directory of the repository.

Example 1: One step and multiple command lines
----------------------------------------------

This is an example on how to prepare the inputs for BWA and run it along with Samtools:

**pipeline.yml**
```yaml
pipeline: resequencing

resources:
  bwa: /software/bwa
  samtools: /software/samtools
  pigz: /software/pigz

steps:
  mapping:
    run:
     - ls <sample_path>/*_R1_*.gz | xargs zcat | <pigz> -p 10 >> R1.fastq.gz
     - ls <sample_path>/*_R2_*.gz | xargs zcat | <pigz> -p 10 >> R2.fastq.gz
     - <bwa> sampe -P <index> <(<bwa> aln -t 4 -q 20 <index> R1.fastq.gz) <(<bwa> aln -t 4 -q 20 <index> R2.fastq.gz) R1.fastq.gz R2.fastq.gz | <samtools> view -Sb - > <sample>.bam
     - rm -f R1.fastq.gz R2.fastq.gz
    cpu: 12
```

**samples.yml**
```yaml
resources:
  index: /storage/genomes/bwa_index/genome
  genome: /storage/genomes/genome.fa
  output: ./working

samples:
  sampleA: /ngs_reads/sampleA
  sampleB: /ngs_reads/sampleB
  sampleC: /ngs_reads/sampleC
  sampleD: /ngs_reads/sampleD
```

Running PipEngine with the following command line:

```
pipengine run -p pipeline.yml -f samples.yml -s mapping -d
```

will generate a runnable shell script for each sample:

```shell
#!/usr/bin/env bash
#PBS -N 2c57c1a853-sampleA-mapping
#PBS -d ./working
#PBS -l nodes=1:ppn=12
if [ ! -f ./working/sampleA/mapping/checkpoint ]
then
echo "mapping 2c57c1a853-sampleA-mapping start `whoami` `hostname` `pwd` `date`."

mkdir -p ./working/sampleA/mapping
cd ./working/sampleA/mapping
ls /ngs_reads/sampleA/*_R1_*.gz | xargs zcat | /software/pigz -p 10 >> R1.fastq.gz || { echo "mapping 2c57c1a853-sampleA-mapping FAILED 0 `whoami` `hostname` `pwd` `date`."; exit 1; }
ls /ngs_reads/sampleA/*_R2_*.gz | xargs zcat | /software/pigz -p 10 >> R2.fastq.gz || { echo "mapping 2c57c1a853-sampleA-mapping FAILED 1 `whoami` `hostname` `pwd` `date`."; exit 1; }
/software/bwa sampe -P /storage/genomes/bwa_index/genome <(/software/bwa aln -t 4 -q 20 /storage/genomes/bwa_index/genome R1.fastq.gz) <(/software/bwa aln -t 4 -q 20 /storage/genomes/bwa_index/genome R2.fastq.gz) R1.fastq.gz R2.fastq.gz | /software/samtools view -Sb - > sampleA.bam || { echo "mapping 2c57c1a853-sampleA-mapping FAILED 2 `whoami` `hostname` `pwd` `date`."; exit 1; }
rm -f R1.fastq.gz R2.fastq.gz || { echo "mapping 2c57c1a853-sampleA-mapping FAILED 3 `whoami` `hostname` `pwd` `date`."; exit 1; }
echo "mapping 2c57c1a853-sampleA-mapping finished `whoami` `hostname` `pwd` `date`."
touch ./working/sampleA/mapping/checkpoint
else
echo "mapping 2c57c1a853-sampleA-mapping already executed, skipping this step `whoami` `hostname` `pwd` `date`."
fi
```
As you can see the command line described in the pipeline YAML are translated into normal Unix command lines, therefore every solution that works on a standard Unix shell (pipes, bash substitutions) is perfectly acceptable. Pipengine addes extra lines in the script for steps checkpoint controls to avoid re-running already executed steps, and error controls with logging.

In this case also, the **run** key defines three different command lines, that are described using YAML array (a line prepended with a -). This command lines are all part of the same step, since the first two are required to prepare the input for the third command line (BWA), using standard bash commands.

As a rule of thumb you should put more command line into an array under the same step if these are all logically correlated and required to manipulate intermidiate files. Otherwise if command lines executes conceptually different actions they should go into different steps.

Example 2: Multiple steps in one job
------------------------------------

Now I want to execute more steps in a single job for each sample. The pipeline YAML is defined in this way:

```yaml

pipeline: resequencing

resources:
  bwa: /software/bwa
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
    cpu: 12

  mark_dup:
    pre: mapping
    run: java -Xmx4g -jar <mark_dup> VERBOSITY=INFO MAX_RECORDS_IN_RAM=500000 VALIDATION_STRINGENCY=SILENT INPUT=<mapping/sample>.sorted.bam OUTPUT=<sample>.md.sort.bam METRICS_FILE=<sample>.metrics REMOVE_DUPLICATES=false

  realign_target:
    pre: mark_dup
    run: java -Xmx4g -jar <gatk> -T RealignerTargetCreator -I <mark_dup/sample>.md.sort.bam -nt 8 -R <genome> -o <sample>.indels.intervals
    cpu: 8
```

The sample YAML file is the same as the example above. Now to execute together the 3 steps defined in the pipeline, PipEngine must be invoked with this command line:

```
pipengine run -p pipeline_multi.yml  -f samples.yml -s realign_target -d
```

And this will be translated into the following shell script (one for each sample):

```shell
#!/usr/bin/env bash
#PBS -N 6f3c911c49-sampleC-realign_target
#PBS -d ./working
#PBS -l nodes=1:ppn=12
if [ ! -f ./working/sampleC/mapping/checkpoint ]
then
echo "mapping 6f3c911c49-sampleC-realign_target start `whoami` `hostname` `pwd` `date`."

mkdir -p ./working/sampleC/mapping
cd ./working/sampleC/mapping
ls /ngs_reads/sampleC/*_R1_*.gz | xargs zcat | pigz -p 10 >> R1.fastq.gz || { echo "mapping 6f3c911c49-sampleC-realign_target FAILED 0 `whoami` `hostname` `pwd` `date`."; exit 1; }
ls /ngs_reads/sampleC/*_R2_*.gz | xargs zcat | pigz -p 10 >> R2.fastq.gz || { echo "mapping 6f3c911c49-sampleC-realign_target FAILED 1 `whoami` `hostname` `pwd` `date`."; exit 1; }
/software/bwa sampe -P /storage/genomes/bwa_index/genome <(/software/bwa aln -t 4 -q 20 /storage/genomes/bwa_index/genome R1.fastq.gz) <(/software/bwa aln -t 4 -q 20 /storage/genomes/bwa_index/genome R2.fastq.gz) R1.fastq.gz R2.fastq.gz | /software/samtools view -Su - | java -Xmx4g -jar /storage/software/picard-tools-1.77/AddOrReplaceReadGroups.jar I=/dev/stdin O=sampleC.sorted.bam SO=coordinate LB=sampleC PL=illumina PU=PU SM=sampleC TMP_DIR=/data/tmp CREATE_INDEX=true MAX_RECORDS_IN_RAM=1000000 || { echo "mapping 6f3c911c49-sampleC-realign_target FAILED 2 `whoami` `hostname` `pwd` `date`."; exit 1; }
rm -f R1.fastq.gz R2.fastq.gz || { echo "mapping 6f3c911c49-sampleC-realign_target FAILED 3 `whoami` `hostname` `pwd` `date`."; exit 1; }
echo "mapping 6f3c911c49-sampleC-realign_target finished `whoami` `hostname` `pwd` `date`."
touch ./working/sampleC/mapping/checkpoint
else
echo "mapping 6f3c911c49-sampleC-realign_target already executed, skipping this step `whoami` `hostname` `pwd` `date`."
fi
if [ ! -f ./working/sampleC/mark_dup/checkpoint ]
then
echo "mark_dup 6f3c911c49-sampleC-realign_target start `whoami` `hostname` `pwd` `date`."

mkdir -p ./working/sampleC/mark_dup
cd ./working/sampleC/mark_dup
java -Xmx4g -jar /software/picard-tools-1.77/MarkDuplicates.jar VERBOSITY=INFO MAX_RECORDS_IN_RAM=500000 VALIDATION_STRINGENCY=SILENT INPUT=./working/sampleC/mapping/sampleC.sorted.bam OUTPUT=sampleC.md.sort.bam METRICS_FILE=sampleC.metrics REMOVE_DUPLICATES=false || { echo "mark_dup 6f3c911c49-sampleC-realign_target FAILED `whoami` `hostname` `pwd` `date`."; exit 1; }
echo "mark_dup 6f3c911c49-sampleC-realign_target finished `whoami` `hostname` `pwd` `date`."
touch ./working/sampleC/mark_dup/checkpoint
else
echo "mark_dup 6f3c911c49-sampleC-realign_target already executed, skipping this step `whoami` `hostname` `pwd` `date`."
fi
if [ ! -f ./working/sampleC/realign_target/checkpoint ]
then
echo "realign_target 6f3c911c49-sampleC-realign_target start `whoami` `hostname` `pwd` `date`."

mkdir -p ./working/sampleC/realign_target
cd ./working/sampleC/realign_target
java -Xmx4g -jar /software/GenomeAnalysisTK/GenomeAnalysisTK.jar -T RealignerTargetCreator -I ./working/sampleC/mark_dup/sampleC.md.sort.bam -nt 8 -R /storage/genomes/genome.fa -o sampleC.indels.intervals || { echo "realign_target 6f3c911c49-sampleC-realign_target FAILED `whoami` `hostname` `pwd` `date`."; exit 1; }
echo "realign_target 6f3c911c49-sampleC-realign_target finished `whoami` `hostname` `pwd` `date`."
touch ./working/sampleC/realign_target/checkpoint
else
echo "realign_target 6f3c911c49-sampleC-realign_target already executed, skipping this step `whoami` `hostname` `pwd` `date`."
fi
```

Since dependencies have been defined for the steps using the ```pre``` key, it is sufficient to invoke Pipengine with the last step and the other two are automatically included in the script.

Logging
---------------------------

It is always usefult to log activities and collect the output from your software. Pipengine can log to:

* stdin, just print on the terminal
* syslog send the log to the system log using logger
* fluentd send the log to a collector/centralized logging system (http://fluentd.org)


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

Note also that from version 0.5.2, it is possible to specify common PBS options like "nodes" and "mem" (for memory) directly within a step defition in the Pipeline yaml, exactly as it's done with the "cpu" parameter. So in a step it is possible to write:

```yaml
  realign_target:
    run: java -Xmx4g -jar <gatk> -T RealignerTargetCreator -I <mark_dup/sample>.md.sort.bam -nt 8 -R <genome> -o <sample>.indels.intervals
    cpu: 8
    nodes: 2
    mem: 8G
```

to have PipEngine translate this into:

```shell
#PBS -l nodes=2:ppn=8,mem=8G
```

within the job script.

If a specific queue needs to be selected for sending the jobs to PBS, the ```--pbs-queue``` (short version **-q**) parameter can be used. This will pass to the ```qsub``` command the ```-q <queue name>``` taken from the command line.

:: Extending and contributing ::
================================

Pipengine code is organized around main methods allowing for YAML parsing and command line arguments substitutions that are available in lib/bio/pipengine.rb. Specific logic for jobs, pipeline steps and samples is described in dedicated classes called Bio::Pipengine::Job, Bio::Pipengine::Step and Bio::Pipengine::Sample.

For instance, in case the support for different schedulers needs to be introduced, it will be sufficient to modify or extend the Job.to_script method, which is the one defining scheduler-specific options in the runnable bash script.

Copyright
=========

&copy;2017 Francesco Strozzi, Raoul Jean Pierre Bonnal 
