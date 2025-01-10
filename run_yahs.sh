#!/bin/bash

################################ START OF YAHS SCAFFOLDING TEST ################################
#### download the test data
## test is either "LYZE01" or "CHM13"
test="LYZE01"
#test="CHM13"
wget https://zenodo.org/record/7079219/files/${test}.contigs.fasta.gz
wget https://zenodo.org/record/7079219/files/${test}.contigs.fasta.gz.fai
wget https://zenodo.org/record/7079219/files/${test}.hic.qn.bam

out="test_out"
outdir="."
contigs="${test}.contigs.fasta.gz" # need to be indexed, i.e., ${test}.contigs.fasta.gz.fai is presented
hicaln="${test}.hic.qn.bam" # could be .bed, .bam or .bin file

#### run yahs scaffolding
../yahs -o ${outdir}/${out} ${contigs} ${hicaln} || exit 1
## LYZE01 is a very small genome, 
## better result when running YaHS with option "-r 1000,2000,5000,10000,20000,50000,100000,200000,500000"
#../yahs -r 1000,2000,5000,10000,20000,50000,100000,200000,500000 -o ${outdir}/${out} ${contigs} ${hicaln} || exit 1
################################# END OF YAHS SCAFFOLDING TEST #################################

#### change doplot to 1 if you want to generate hic contact maps
## you also need to set the path of juicer_tools, pretext_map, pretext_snapshot, and samtools
doplot=0
if [ ${doplot} -eq 0 ]; then exit 0; fi

## need juicer_tools/pretextmap and samtools if want to do hic plot
## juicer_tools: https://github.com/aidenlab/juicer/wiki/Download
## PretextMap: https://github.com/wtsi-hpag/PretextMap
## PretexSnapshot: https://github.com/wtsi-hpag/PretextSnapshot
## samtools: https://github.com/samtools/samtools
## please adjust the path to juicer_tools and samtools
## here we use 12 CPUs and 32Gb memory for juicer_tools pre - adjust it according to your device
## see more information for juicer tools https://github.com/aidenlab/juicer/wiki/Juicer-Tools-Quick-Start
## output file will be ${outdir}/${out}.hic
## the output hic file could be viewed with JuiceBox https://github.com/aidenlab/Juicebox
#juicer_tools="java -Xmx32G -jar /bin/juicer_tools_1.22.01.jar pre --threads 12"
## v1.9.9 seems much faster than v1.22.01
juicer_tools="java -Xmx32G -jar /bin/juicer_tools.1.9.9_jcuda.0.8.jar pre"
pretext_map="/bin/PretextMap"
pretext_snapshot="/bin/PretextSnapshot"
samtools="/bin/samtools"

#### this is to generate input file for juicer_tools - non-assembly mode or for PretextMap
## here we use 8 CPUs and 32Gb memory for sorting - adjust it according to your device
(../juicer pre ${outdir}/${out}.bin ${outdir}/${out}_scaffolds_final.agp ${contigs}.fai 2>${outdir}/tmp_juicer_pre.log | LC_ALL=C sort -k2,2d -k6,6d -T ${outdir} --parallel=8 -S32G | awk 'NF' > ${outdir}/alignments_sorted.txt.part) && (mv ${outdir}/alignments_sorted.txt.part ${outdir}/alignments_sorted.txt)
## prepare chromosome size file from samtools index file
# ${samtools} faidx ${outdir}/${out}_scaffolds_final.fa
# cut -f1-2 ${outdir}/${out}_scaffolds_final.fa.fai >${outdir}/${out}_scaffolds_final.chrom.sizes
## another way to prepare chromosome size file
## this is an easier way especially when we have >2G scaffolds which need scaling 
cat ${outdir}/tmp_juicer_pre.log | grep "PRE_C_SIZE" | cut -d' ' -f2- >${outdir}/${out}_scaffolds_final.chrom.sizes
## do juicer hic map
(${juicer_tools} ${outdir}/alignments_sorted.txt ${outdir}/${out}.hic.part ${outdir}/${out}_scaffolds_final.chrom.sizes) && (mv ${outdir}/${out}.hic.part ${outdir}/${out}.hic)
## do Pretext hic map
(awk 'BEGIN{print "## pairs format v1.0"} {print "#chromsize:\t"$1"\t"$2} END {print "#columns:\treadID\tchr1\tpos1\tchr2\tpos2\tstrand1\tstrand2"}' ${outdir}/${out}_scaffolds_final.chrom.sizes; awk '{print ".\t"$2"\t"$3"\t"$6"\t"$7"\t.\t."}' alignments_sorted.txt) | ${pretext_map} -o ${outdir}/${out}.pretext
# and a pretext snapshot
${pretext_snapshot} -m ${outdir}/${out}.pretext --sequences "=full" -o ${outdir}

#### this is to generate input file for juicer_tools - assembly (JBAT) mode (-a)
../juicer pre -a -o ${outdir}/${out}_JBAT ${outdir}/${out}.bin ${outdir}/${out}_scaffolds_final.agp ${contigs}.fai 2>${outdir}/tmp_juicer_pre_JBAT.log
cat ${outdir}/tmp_juicer_pre_JBAT.log | grep "PRE_C_SIZE" | cut -d' ' -f2- >${outdir}/${out}_JBAT.chrom.sizes
(${juicer_tools} ${outdir}/${out}_JBAT.txt ${outdir}/${out}_JBAT.hic.part ${outdir}/${out}_JBAT.chrom.sizes) && (mv ${outdir}/${out}_JBAT.hic.part ${outdir}/${out}_JBAT.hic)

#### this is to generate final genome assembly file after manual curation with JuiceBox (JBAT)
## the output assembly file after curation is ${outdir}/${out}_JBAT.review.assembly
## the final output is ${outdir}/${out}_JBAT.FINAL.agp and ${outdir}/${out}_JBAT.FINAL.fa
# ../juicer post -o ${outdir}/${out}_JBAT ${outdir}/${out}_JBAT.review.assembly ${outdir}/${out}_JBAT.liftover.agp ${contigs}

