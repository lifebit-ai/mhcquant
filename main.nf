#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/mhcquant
========================================================================================
 nf-core/mhcquant Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/mhcquant
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    log.info"""
    =======================================================
                                              ,--./,-.
              ___     __   __   __   ___     /,-._.--~\'
        |\\ | |__  __ /  ` /  \\ |__) |__         }  {
        | \\| |       \\__, \\__/ |  \\ |___     \\`-._,-`-,
                                              `._,._,\'

     nf-core/mhcquant : v${workflow.manifest.version}
    =======================================================
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/mhcquant --mzmls '*.mzML' --fasta '*.fasta' -profile standard,docker

    Mandatory arguments:
      --mzmls                       Path to input data (must be surrounded with quotes)
      --fasta                       Path to Fasta reference
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: standard, conda, docker, singularity, awsbatch, test

    Options:
      --precursor_mass_tolerance    Mass tolerance of precursor mass (ppm)
      --fragment_mass_tolerance     Mass tolerance of fragment mass bin (ppm)
      --fragment_bin_offset         Offset of fragment mass bin (Comet specific parameter)
      --fdr_threshold               Threshold for FDR filtering
      --fdr_level                   Level of FDR calculation ('peptide-level-fdrs', 'psm-level-fdrs', 'protein-level-fdrs')
      --digest_mass_range           Mass range of peptides considered for matching
      --activation_method           Fragmentation method ('ALL', 'CID', 'ECD', 'ETD', 'PQD', 'HCD', 'IRMPD')
      --enzyme                      Enzymatic cleavage ('unspecific cleavage', 'Trypsin', see OpenMS enzymes)
      --number_mods                 Maximum number of modifications of PSMs
      --fixed_mods                  Fixed modifications ('Carbamidomethyl (C)', see OpenMS modifications)
      --variable_mods               Variable modifications ('Oxidation (M)', see OpenMS modifications)
      --num_hits                    Number of reported hits
      --centroided                  Specify whether mzml data is peak picked or not ("True", "False")
      --pick_ms_levels              The ms level used for peak picking (eg. 1, 2)
      --prec_charge                 Precursor charge (eg. "2:3")


    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Show help emssage
if (params.help){
    helpMessage()
    exit 0
}


// Validate inputs
params.mzmls_folder = params.mzmls_folder ?: { log.error "No read data privided. Make sure you have used the '--mzmls' option."; exit 1 }()
params.fasta = params.fasta ?: { log.error "No read data privided. Make sure you have used the '--fasta' option."; exit 1 }()
params.outdir = params.outdir ?: { log.warn "No output directory provided. Will put the results into './results'"; return "./results" }()



/*
 * Define the default parameters
 */

params.fragment_mass_tolerance = 0.02
params.precursor_mass_tolerance = 5
params.fragment_bin_offset = 0
params.fdr_threshold = 0.01
params.fdr_level = 'peptide-level-fdrs'
fdr_level = '-' + params.fdr_level
params.number_mods = 3

params.num_hits = 1
params.digest_mass_range = "800:2500"
params.pick_ms_levels = 2
params.centroided = "False"

params.prec_charge = '2:3'
params.activation_method = 'ALL'

params.enzyme = 'unspecific cleavage'
params.fixed_mods = ''
params.variable_mods = 'Oxidation (M)'


/*
 * SET UP CONFIGURATION VARIABLES
 */


// Configurable variables
params.name = false
params.email = false
params.plaintext_email = false

output_docs = file("$baseDir/docs/output.md")


// AWSBatch sanity checking
if(workflow.profile == 'awsbatch'){
    if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
    if (!workflow.workDir.startsWith('s3') || !params.outdir.startsWith('s3')) exit 1, "Specify S3 URLs for workDir and outdir parameters on AWSBatch!"
}


// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}

// Check workDir/outdir paths to be S3 buckets if running on AWSBatch
// related: https://github.com/nextflow-io/nextflow/issues/813
if( workflow.profile == 'awsbatch') {
    if(!workflow.workDir.startsWith('s3:') || !params.outdir.startsWith('s3:')) exit 1, "Workdir or Outdir not on S3 - specify S3 Buckets for each to run on AWSBatch!"
}


/*
 * Create a channel for input mzml files
 */
 mzmls="${params.mzmls_folder}/*.${params.mzmls_extension}"
Channel
    .fromPath(mzmls)
    .ifEmpty { exit 1, "Cannot find any reads matching: ${mzmls}\nNB: Path needs to be enclosed in quotes!" }
    .into { input_mzmls; input_mzmls_align }


/*
 * Create a channel for input fasta file
 */
Channel
    .fromPath( params.fasta )
    .ifEmpty { exit 1, "params.fasta was empty - no input file supplied" }
    .set { input_fasta}


// Header log info
log.info """=======================================================
                                          ,--./,-.
          ___     __   __   __   ___     /,-._.--~\'
    |\\ | |__  __ /  ` /  \\ |__) |__         }  {
    | \\| |       \\__, \\__/ |  \\ |___     \\`-._,-`-,
                                          `._,._,\'

nf-core/mhcquant v${workflow.manifest.version}"
======================================================="""
def summary = [:]
summary['Pipeline Name']  = 'nf-core/mhcquant'
summary['Pipeline Version'] = workflow.manifest.version
summary['Run Name']     = custom_runName ?: workflow.runName
summary['mzMLs']        = params.mzmls
summary['Fasta Ref']    = params.fasta
summary['Max Memory']   = params.max_memory
summary['Max CPUs']     = params.max_cpus
summary['Max Time']     = params.max_time
summary['Output dir']   = params.outdir
summary['Working dir']  = workflow.workDir
summary['Container Engine'] = workflow.containerEngine
if(workflow.containerEngine) summary['Container'] = workflow.container
summary['Current home']   = "$HOME"
summary['Current user']   = "$USER"
summary['Current path']   = "$PWD"
summary['Working dir']    = workflow.workDir
summary['Output dir']     = params.outdir
summary['Script dir']     = workflow.projectDir
summary['Config Profile'] = workflow.profile
if(workflow.profile == 'awsbatch'){
   summary['AWS Region'] = params.awsregion
   summary['AWS Queue'] = params.awsqueue
}
if(params.email) summary['E-mail Address'] = params.email
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="


def create_workflow_summary(summary) {

    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nf-core-mhcquant-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/mhcquant Workflow Summary'
    section_href: 'https://github.com/nf-core/mhcquant'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}


/*
 * STEP 1 - generate reversed decoy database
 */
process generate_decoy_database {

    input:
     file fastafile from input_fasta

    output:
     file "${fastafile.baseName}_decoy.fasta" into (fastafile_decoy_1, fastafile_decoy_2)

    script:
     """
     DecoyDatabase  -in ${fastafile} -out ${fastafile.baseName}_decoy.fasta -decoy_string DECOY_ -decoy_string_position prefix
     """
}


/*
 * STEP 2 - run comet database search
 */
process db_search_comet {

    input:
     file mzml_file from input_mzmls
     file fasta_decoy from fastafile_decoy_1.first()

    output:
     file "${mzml_file.baseName}.idXML" into id_files

    script:
     """
     CometAdapter  -in ${mzml_file} -out ${mzml_file.baseName}.idXML -threads ${task.cpus} -database ${fasta_decoy} -precursor_mass_tolerance ${params.precursor_mass_tolerance} -fragment_bin_tolerance ${params.fragment_mass_tolerance} -fragment_bin_offset ${params.fragment_bin_offset} -num_hits ${params.num_hits} -digest_mass_range ${params.digest_mass_range} -max_variable_mods_in_peptide ${params.number_mods} -allowed_missed_cleavages 0 -precursor_charge ${params.prec_charge} -activation_method ${params.activation_method} -use_NL_ions true -variable_modifications '${params.variable_mods}' -fixed_modifications ${params.fixed_mods} -enzyme '${params.enzyme}'
     """

}


/*
 * STEP 3 - index decoy and target hits
 */
process index_peptides {
    publishDir "${params.outdir}/"

    input:
     file id_file from id_files
     file fasta_decoy from fastafile_decoy_2.first()

    output:
     file "${id_file.baseName}_idx.idXML" into (id_files_idx, id_files_idx_original)

    script:
     """
     PeptideIndexer -in ${id_file} -out ${id_file.baseName}_idx.idXML -threads ${task.cpus} -fasta ${fasta_decoy} -decoy_string DECOY -enzyme:specificity none
     """

}


/*
 * STEP 4 - calculate fdr for id based alignment
 */
process calculate_fdr_for_idalignment {
    publishDir "${params.outdir}/"

    input:
     file id_file_idx from id_files_idx

    output:
     file "${id_file_idx.baseName}_fdr.idXML" into id_files_idx_fdr

    script:
     """
     FalseDiscoveryRate -in ${id_file_idx} -out ${id_file_idx.baseName}_fdr.idXML -threads ${task.cpus}
     """

}


/*
 * STEP 5 - filter fdr for id based alignment
 */
process filter_fdr_for_idalignment {
    publishDir "${params.outdir}/"

    input:
     file id_file_idx_fdr from id_files_idx_fdr

    output:
     file "${id_file_idx_fdr.baseName}_filtered.idXML" into id_files_idx_fdr_filtered

    script:
     """
     IDFilter -in ${id_file_idx_fdr} -out ${id_file_idx_fdr.baseName}_filtered.idXML -threads ${task.cpus} -score:pep 0.05  -remove_decoys
     """

}


/*
 * STEP 6 - compute alignment rt transformation
 */
process align_ids {
   publishDir "${params.outdir}/"

    input:
     file id_names from id_files_idx_fdr_filtered.collect{it}

    output:
     file '*.trafoXML' into (id_files_trafo_mzml, id_files_trafo_idxml)

    script:
     def out_names = id_names.collect { it.baseName+'.trafoXML' }.join(' ')
     """
     MapAlignerIdentification -in $id_names -trafo_out $out_names
     """

}


/*
 * STEP 7 - align mzML files using trafoXMLs
 */
process align_mzml_files {
    publishDir "${params.outdir}/"

    input:
     file id_file_trafo from id_files_trafo_mzml.flatten()
     file mzml_file_align from input_mzmls_align

    output:
     file "${mzml_file_align.baseName}_aligned.mzML" into mzml_files_aligned

    script:
     """
     MapRTTransformer -in ${mzml_file_align} -trafo_in ${id_file_trafo} -out ${mzml_file_align.baseName}_aligned.mzML -threads ${task.cpus}
     """

}


/*
 * STEP 8 - align unfiltered idXMLfiles using trafoXMLs
 */
process align_idxml_files {
    publishDir "${params.outdir}/"

    input:
     file idxml_file_trafo from id_files_trafo_idxml.flatten()
     file idxml_file_align from id_files_idx_original

    output:
     file "${idxml_file_align.baseName}_aligned.idXML" into idxml_files_aligned

    script:
     """
     MapRTTransformer -in ${idxml_file_align} -trafo_in ${idxml_file_trafo} -out ${idxml_file_align.baseName}_aligned.idXML -threads ${task.cpus}
     """

}


/*
 * STEP 9 - merge aligned idXMLfiles
 */
process merge_aligned_idxml_files {
    publishDir "${params.outdir}/"

    input:
     file ids_aligned from idxml_files_aligned.collect{it}

    output:
     file "all_ids_merged.idXML" into id_merged

    script:
     """
     IDMerger -in $ids_aligned -out all_ids_merged.idXML -threads ${task.cpus}  -annotate_file_origin
     """

}


/*
 * STEP 10 - extract PSM features for Percolator
 */
process extract_psm_features_for_percolator {
    publishDir "${params.outdir}/"

    input:
     file id_file_merged from id_merged

    output:
     file "${id_file_merged.baseName}_psm.idXML" into id_files_merged_psm

    script:
     """
     PSMFeatureExtractor -in ${id_file_merged} -out ${id_file_merged.baseName}_psm.idXML -threads ${task.cpus}
     """

}


/*
 * STEP 11 - run Percolator
 */

///To Do: add peptide level variable
process run_percolator {
    publishDir "${params.outdir}/"

    input:
     file id_file_psm from id_files_merged_psm

    output:
     file "${id_file_psm.baseName}_psm_perc.idXML" into id_files_merged_psm_perc

    script:
     """
     PercolatorAdapter -in ${id_file_psm} -out ${id_file_psm.baseName}_psm_perc.idXML -trainFDR 0.05 -testFDR 0.05 -threads ${task.cpus} -enzyme no_enzyme $fdr_level
     """

}


/*
 * STEP 12 - filter by percolator q-value
 */
process filter_q_value {
    publishDir "${params.outdir}/"

    input:
     file id_file_perc from id_files_merged_psm_perc

    output:
     file "${id_file_perc.baseName}_psm_perc_filtered.idXML" into id_files_merged_psm_perc_filtered

    script:
     """
     IDFilter -in ${id_file_perc} -out ${id_file_perc.baseName}_psm_perc_filtered.idXML -threads ${task.cpus} -score:pep 9999  -remove_decoys
     """

}


/*
 * STEP 13 - quantify identifications using targeted feature extraction
 */
process quantify_identifications_targeted {
    publishDir "${params.outdir}/"

    input:
     file id_file_quant from id_files_merged_psm_perc_filtered
     file mzml_quant from mzml_files_aligned

    output:
     file "${mzml_quant.baseName}.featureXML" into (feature_files, feature_files_2)

    script:
     """
     FeatureFinderIdentification -in ${mzml_quant} -id ${id_file_quant} -out ${mzml_quant.baseName}.featureXML -threads ${task.cpus}
     """

}


/*
 * STEP 14 - link extracted features
 */
process link_extracted_features {
    publishDir "${params.outdir}/"

    input:
     file feautres from feature_files.collect{it}

    output:
     file "all_features_merged.consensusXML" into consensus_file

    script:
     """
     FeatureLinkerUnlabeledKD -in $feautres -out 'all_features_merged.consensusXML' -threads ${task.cpus}
     """

}


/*
 * STEP 15 - resolve conflicting ids matching to the same feature
 */
process resolve_conflicts {
    publishDir "${params.outdir}/"

    input:
     file consensus from consensus_file

    output:
     file "${consensus.baseName}_resolved.consensusXML" into (consensus_file_resolved, consensus_file_resolved_2)

    script:
     """
     IDConflictResolver -in ${consensus} -out ${consensus.baseName}_resolved.consensusXML -threads ${task.cpus}
     """

}


/*
 * STEP 16 - export all information as text to csv
 */
process export_text {
    publishDir "${params.outdir}/"

    input:
     file consensus_resolved from consensus_file_resolved

    output:
     file "${consensus_resolved.baseName}.csv" into consensus_text

    script:
     """
     TextExporter -in ${consensus_resolved} -out ${consensus_resolved.baseName}.csv -threads ${task.cpus} -id:add_hit_metavalues 0 -id:add_metavalues 0 -id:peptides_only
     """

}


/*
 * STEP 17 - export all information as mzTab
 */
process export_mztab {
    publishDir "${params.outdir}/"

    input:
     file feature_file_2 from consensus_file_resolved_2

    output:
     file "${feature_file_2.baseName}.mzTab" into features_mztab

    script:
     """
     MzTabExporter -in ${feature_file_2} -out ${feature_file_2.baseName}.mzTab -threads ${task.cpus}
     """

}


/*
 * STEP 18 - generate JSON report to display on Deploit
 */
process visualisations {
    publishDir "${params.outdir}/Visualisations", mode: 'copy'

    container 'lifebitai/vizjson:latest'

    input:
    set file(consensus) from consensus_text

    output:
    file '.report.json' into viz

    script:
    """
    echo -e "MAP\tid\tfilename\tlabel\tsize" > map.tsv
    awk -F"\t" '\$1 == "MAP" { print \$0 }' all_features_merged_resolved.csv >> map.tsv
    tsv2csv.py < map.tsv > tmp.csv
    cut -d',' -f 2- tmp.csv > map.csv
    csv2json.py map.csv "A table to show the different mzML files that were provided initially" map.json

    echo -e "RUN\trun_id\tscore type\tscore direction\tdate time\tsearch engine version\tparameters" > run.tsv
    awk -F"\t" '\$1 == "RUN" { print \$0 }' all_features_merged_resolved.csv >> run.tsv
    tsv2csv.py < run.tsv > tmp.csv
    cut -d',' -f 2- tmp.csv > run.csv
    csv2json.py run.csv "A table to show the search that was performed on each run" run.json

    echo -e "PROTEIN\tscore\trank\taccession\tprotein_description\tcoverage\tsequence" > protein.tsv
    awk -F"\t" '\$1 == "PROTEIN" { print \$0 }' all_features_merged_resolved.csv >> protein.tsv
    tsv2csv.py < protein.tsv > tmp.csv
    cut -d',' -f 2- tmp.csv > protein.csv
    csv2json.py protein.csv "A table to show the protein ids corresponding to the peptides that were detected (No protein inference was performed)" protein.json

    echo -e "UNASSIGNEDPEPTIDE\trt\tmz\tscore\trank\tsequence\tcharge\taa before\taa after\tscore type\tsearch identifier\taccessions\tFFId category\tfeature id\tfile origin\tmap index\tspectrum reference\tCOMET:IonFrac\tCOMET:deltCn\tCOMET:deltLCn\tCOMET:lnExpect\tCOMET:lnNumSP\tCOMET:lnRankSP\tMS:1001491\tMS:1001492\tMS:1001493\tMS:1002252\tMS:1002253\tMS:1002254\tMS:1002255\tMS:1002256\tMS:1002257\tMS:1002258\tMS:1002259\tnum matched peptides\tprotein references\ttarget decoy" > unassigned.tsv
    awk -F"\t" '\$1 == "UNASSIGNEDPEPTIDE" { print \$0 }' all_features_merged_resolved.csv >> unassigned.tsv
    tsv2csv.py < unassigned.tsv > tmp.csv
    cut -d',' -f 2- tmp.csv > unassigned.csv
    csv2json.py unassigned.csv "A table to show the PSMs that were identified but couldn't be quantified to a precursor feature on MS Level 1" unassigned.json

    echo -e "CONSENSUS\trt cf\tmz cf\tintensity cf\tcharge cf\twidth cf\tquality cf\trt 0\tmz 0\tintensity 0\tcharge 0\twidth 0\trt 1\tmz 1\tintensity 1\tcharge 1\twidth 1\trt 2\tmz 2\tintensity 2\tcharge 2\twidth 2\trt 3\tmz 3\tintensity 3\tcharge 3\twidth 3" > consensus.tsv
    awk -F"\t" '\$1 == "CONSENSUS" { print \$0 }' all_features_merged_resolved.csv >> consensus.tsv
    tsv2csv.py < consensus.tsv > tmp.csv
    cut -d',' -f 2- tmp.csv > consensus.csv
    csv2json.py consensus.csv "A table to show the precursor features that were identified in multiple runs" consensus.json

    echo -e "PEPTIDE\trt\tmz\tscore\trank\tsequence\tcharge\taa before\taa after\tscore type\tsearch identifier\taccessions\tFFId category\tfeature id\tfile origin\tmap index\tspectrum reference\tCOMET:IonFrac\tCOMET:deltCn\tCOMET:deltLCn\tCOMET:lnExpect\tCOMET:lnNumSP\tCOMET:lnRankSP\tMS:1001491\tMS:1001492\tMS:1001493\tMS:1002252\tMS:1002253\tMS:1002254\tMS:1002255\tMS:1002256\tMS:1002257\tMS:1002258\tMS:1002259\tnum matched peptides\tprotein references\ttarget decoy" > peptide.tsv
    awk -F"\t" '\$1 == "PEPTIDE" { print \$0 }' all_features_merged_resolved.csv >> peptide.tsv
    tsv2csv.py < peptide.tsv > tmp.csv
    cut -d',' -f 2- tmp.csv > peptide.csv
    csv2json.py peptide.csv "Table to show the peptide hits that were identified and correspond to the consensus features table" peptide.json
    
    combine_reports.py .
    """
}

/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/mhcquant] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[nf-core/mhcquant] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir" ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[nf-core/mhcquant] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[nf-core/mhcquant] Sent summary e-mail to $params.email (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/Documentation/" )
    if( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    log.info "[nf-core/mhcquant] Pipeline Complete"

}
