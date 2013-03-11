PipEngine
=========

A simple launcher for complex biological pipelines.

The idea under PipEngine is to create a simple solution to define reusable pipelines that can be applied to different input samples. PipEngine is best suited for NGS pipelines, but it can be used for any kind of pipeline that can be runned on a job scheduling system.


Usage
=====

```shell
        --pipeline, -p <s>:   YAML file with pipeline and sample details (default: pipeline.yml)
    --samples-file, -f <s>:   YAML file with samples name and directory paths (default: samples.yml)
        --samples, -l <s+>:   List of sample names to run the pipeline
          --steps, -s <s+>:   List of steps to be executed
                 --dry, -d:   Dry run. Just create the job script without sending it to the batch system
           --local, -o <s>:   Local output root folder
  --create-samples, -c <s>:   Create samples.yml file from a Sample directory (only for CASAVA projects)
         --groups, -g <s+>:   Group of samples to be processed by a given step
            --name, -n <s>:   Analysis name
                --help, -h:   Show this message
```

PipEngine accepts two input files:
* A YAML file describing the pipeline steps
* A YAML file describing samples names, samples location and other samples-specific information

PipEngine will generate a runnable shell script, already configured for the PBS job scheduler, for each sample in the pipeline. It allows to run a complete pipeline or just a single step or a few steps.


The Pipeline YAML
=================

The basic structure of a pipeline YAML file is like the following:

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

step:
  quality:
    run: <fastqc> --casava <sample_path>/*.gz -o <output> --noextract -nt 8
    threads: 8

  mapping:
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

A note on the **run** key. If a single step need more than a command line to execute the required actions, these multiple command lines must be defined as an array in YAML (see the mapping step in the above example).


The Sample YAML
===============

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

Input and output conventions
============================

The ```<output>``` placeholder is a generic one to define the root location for the pipeline outputs.

By convention, each sample output is saved under a folder with the sample name and each step is saved in a sub-folder with the step name.

That is, given a generic /storage/pipeline_results ```<output>``` folder, the outputs of the **mapping** step will be organized in this way:

```shell
/storage/pipeline_results
                         |-SampleA/mapping/SampleA.bam
                         |-SampleB/mapping/SampleB.bam
                         |-SampleC/mapping/SampleC.bam
                         |-SampleD/mapping/SampleD.bam
```

This simple convention keeps things clearer and well organized. The output file name can be decided during the pipeline creation, but it's a good habit to name it using the sample name.

Regarding the input conventions, in the pipeline YAML the ```<sample>``` placeholder will be substituted with the sample name while the ```<sample_path>``` will be changed with the location where initial sample data (i.e. raw sequencing reads) are stored. Both this information are coming from the sample YAML file.




How steps are connected together
--------------------------------

One step is connected to another by simply requiring that its input is coming from the output of another step. This is just achived by a combination of ```<output>``` and ```<sample>``` placeholders in the pipeline command line definitions.

For instance, if I have an RNA-seq pipeline that will first run TopHat to map the reads and then Cufflinks to assemble them, the Cufflinks step will be dependent from the TopHat output.

So in the Cufflinks step the command line input (defined under the **run** key in the pipeline YAML) will be written as:

```
<tophat/sample>_tophat/accepted_hits.bam
```

Given an ```<output>``` tag defined as /storage/results, this will be translated at run-time into:

```
/storage/results/SampleA/tophat/SampleA_tophat/accepted_hits.bam
```

for SampleA. Basically the ```<tophat/sample>``` placeholder is a shortcut for ```<output>/<sample>/{step name, Tophat in this case}/<sample>``` .

More complex dependence can be defined by combinations of ```<output>``` and ```<sample>``` placeholders, without having to worry about the actual sample name and the complete paths of input and output paths.


Sample groups and complex steps
===============================

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

Once the step has been defined in the pipeline YAML, pipengine must be invoked using the **-g** parameter, to specify the samples that should be processed by this step:

```shell
pipengine -p pipeline.yml -g SampleA,SampleB SampleC,SampleB
```

Note that the use of commas is not casual, since the **-g** parameter takes the sample names and underneath it will combine the sample name, with the 'groups' keywords and then it will substitute back the command line by keeping the samples in the same order as provided with the **-g**.

The above command line will be translated, for the **diffexp** step in the following:

```shell
/software/cuffdiff -p 12 -N -u -b /storage/genome.fa combined.gtf /storage/results/SampleA/cufflinks/transcripts.gtf,/storage/results/SampleB/cufflinks/transcripts.gtf /storage/results/SampleC/cufflinks/transcripts.gtf /storage/results/SampleD/cufflinks/transcripts.gtf
```

and this will correspond to the way CuffDiff wants biological replicates for each condition to be described on the command line.


What happens at run-time
========================

When invoking pipengine, the tool will look for the pipeline YAML specified and for the sample YAML file. It will load the list of samples (names and paths of input data) and for each sample it will start loading the corresponding step information specified in the command line.

PipEngine will then combine the data from the two YAML, generating the specific command lines of the selected steps and substituing all the placeholders to generate the final command lines.

A shell script will be finally generated, for each sample, that will contain all the instructions to run a specific step of the pipelines plus the meta data for the PBS scheduler.

If not invoked with the **-d** option (dry-run) PipEngine will directly submit the jobs to the PBS scheduler using the "qsub" command.

Local output folder
-------------------

By using the '--local' option, PipEngine will generate a job script (for each sample) that will save all the output files or folders for a particular step in a local directory (e.g. /tmp).

By default PipEngine, if not invoked with '--local', will generate output folders directly under the location defined by the ```<ouput>``` tag. The local solution can be useful when we don't want to save directly to the final location (e.g a slow network storage) or we don't want to keep all the intermediate files but just the final ones.

With this option enabled, PipEngine will also generate instructions in the job script to copy the final output folder from the local temporary directory to the final output folder (i.e. ```<output>```) and then to remove the local copy.

When '--local' is used a UUID is generated for each job and prepended to the job name and to the local output folder, to avoid possible name collisions and data overwrite if more jobs with the same name (i.e. mapping) are running at the same time.

One job with multiple steps
---------------------------

It is of course possible to aggregate multiple steps of a pipeline and run them in one single job. For instance let's say I want to run in the same job the steps mapping, mark_dup and realign_target (see pipeline YAML example above).

From the command line it's just:

```shell
pipengine -p pipeline.yml -s mapping mark_dup realign_target
```

A single job script, for each sample, will be generated with all the instructions for this steps. If more than one step declares a **cpu** key, the highest cpu value will be assigned for the whole job.

If the pipeline is defined with steps that are dependent one from the other, in the scenario where more steps are run together PipEngine will check if for a given step the expected input is already available. If not, it will assume the input will be found in the current working directory, because the input has not yet been generated.

This is because the output folders are by definition based on the job executed. So one step in one job, means one output folder with the step name, but more steps in one job means that all the outputs generated will be in the same job directory that by default it's named as the concatenation of all the steps executed.

Since this can be a problem when a lot of steps are run together in the same job, a '--name' parameter it's available to rename the job (and thus the corresponding output folder).


Copyright
=========

2013 Francesco Strozzi