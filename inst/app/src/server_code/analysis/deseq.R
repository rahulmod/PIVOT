# PIVOT: Platform for Interactive analysis and Visualization Of Transcriptomics data
# Copyright (c) 2015-2018, Qin Zhu and Junhyong Kim, University of Pennsylvania.
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.



output$deseq_ui <- renderUI({
    if(is.null(r_data$meta) || ncol(r_data$meta) < 2){
        return(
            list(
                tags$li("This module requires design information input.")
            )
        )
    }

    list(
        enhanced_box(
            width = 12,
            title = "DESeq2 Differential Expression Analysis",
            id = "deseq",
            status = "primary",
            solidHeader = T,
            collapsible = T,
            reportable = T,
            get_html = T,
            register_analysis= T,
            tags$div(tags$b("General Settings:"), class = "param_setting_title"),
            fluidRow(
                pivot_deGroupBy_UI("deseq", r_data$meta, width = 12, reduced = "maybe", model = c("condition", "condition_batch", "custom"))
            ),
            fluidRow(
                column(4, uiOutput("deseq_test_method_ui")),
                column(8,
                       uiOutput("deseq_test_explain")
                )
            ),
            fluidRow(
                column(6),
                column(3, checkboxInput("deseq_parallel", "Run with multithread", value=F)),
                column(3, actionButton("perform_deseq", "Run DE", class = "btn-info"))
            )
        ),
        uiOutput("deseq_results_box"),
        enhanced_box(
            width = 12,
            title = NULL,
            status = "primary",
            tags$div(tags$b("MA Plot:"), class = "param_setting_title"),
            plotOutput("deseq_ma_plt", height = "600px")
        ),
        enhanced_box(
            width = 12,
            title = NULL,
            status = "primary",
            solidHeader = F,
            uiOutput("deseq_gene_plot_ui")
        ),
        box(
            width = 12,
            title = "Citation",
            status = "primary",
            tags$ol(
                tags$li("Michael I Love, Wolfgang Huber and Simon Anders (2014): Moderated estimation of fold change and dispersion for RNA-Seq data with DESeq2. Genome Biology.", class = "citation")
            )
        )
    )

})


deseqModel <- callModule(pivot_deGroupBy, "deseq", meta = r_data$meta, reduced = "maybe")

output$deseq_test_method_ui <- renderUI({
    if(!is.null(deseqModel()) && deseqModel()$design == "condition"){
        selectInput("deseq_test_method", "Test Method", choices = list("Wald" = "Wald", "LRT" = "LRT"), selected = "Wald")
    } else {
        selectInput("deseq_test_method", "Test Method", choices = list("LRT" = "LRT"))
    }
})

output$deseq_test_explain <- renderUI({
    req(input$deseq_test_method)
    if(input$deseq_test_method == "Wald") {
        list(
            tags$b("Wald test for the GLM coefficients: "),
            tags$li("This function tests for significance of coefficients in a Negative Binomial GLM."),
            tags$li("Note: This is the default test for DESeq.")
        )
    } else if(input$deseq_test_method == "LRT") {
        list(
            tags$b("Likelihood ratio test (chi-squared test) for GLMs: "),
            tags$li("This function tests for significance of change in deviance between a full and reduced model."),
            tags$li("Note: Useful for testing multiple terms at once, conceptually similar to ANOVA.")
            )
    } else {
        return()
    }
})

observeEvent(input$perform_deseq, {
    req(r_data$meta, deseqModel(), input$deseq_test_method, ncol(r_data$meta) >= 2)

    # Clear previous results if exist
    if(!is.null(r_data$dds)) {
        r_data$dds <- NULL
        r_data$deseq_params <- NULL
        r_data$deseq_group <- NULL
        r_data$deseq_results <- NULL
    }

    withProgress(message = 'Processing...', value = 0.5, {
        error_I <- 0
        # Perform size factor re-estimation if necessary
        tryCatch({
            dds <- DESeq2::DESeqDataSetFromMatrix(
                countData = r_data$raw, colData=r_data$meta[,-1,drop =F],
                design = deseqModel()$model$full)

            # If the data was normalized by DESeq modified, use the new size factor estimation
            if(r_data$norm_param$method == "Modified_DESeq") {
                DESeq2::sizeFactors(dds) <- r_data$norm_param$sizeFactor$size_factor
            } else {
                # If the data was not normalized by DESeq modified, re-estimate size factors using deseq2
                dds <- DESeq2::estimateSizeFactors(dds)
            }
        },
        error = function(e){
            error_I <<- 1
        }
        )

        if(error_I) {
            session$sendCustomMessage(type = "showalert", "DESeq failed.")
            return()
        }

        if(input$deseq_test_method == "Wald") {
            r_data$dds <- DESeq2::DESeq(dds, test="Wald", parallel = input$deseq_parallel)
        } else if(input$deseq_test_method == "LRT") {
            if(is.null(deseqModel()$model$reduced)) {
                session$sendCustomMessage(type = "showalert", "Reduced formula required.")
                return()
            }
            r_data$dds <- DESeq2::DESeq(dds, test = "LRT", reduced = deseqModel()$model$reduced, parallel = input$deseq_parallel)
        }

        r_data$deseq_params <- list(design = deseqModel()$design, test = input$deseq_test_method, model = deseqModel()$model)
    })
})

output$deseq_results_box <- renderUI({
    req(r_data$meta, ncol(r_data$meta) >= 2, r_data$dds)
    options<-DESeq2::resultsNames(r_data$dds)
    options <- options[which(options != "Intercept")]
    names(options) <- options

    enhanced_box(
        width = 12,
        title = NULL,
        status = "primary",
        solidHeader = T,
        tags$div(tags$b("Results Table:"), class = "param_setting_title"),
        selectInput("deseq_result_name", "Choose comparison/individual effect",
                    choices = as.list(options)),
        fluidRow(
            column(4,
                   uiOutput("deseq_test_method_text")
            ),
            column(4, numericInput("deseq_alpha", "FDR cutoff", value = 0.1, min = 0, max = 0.5, step = 0.001)),
            column(4, checkboxInput("deseq_cuttbl", "Only show significant genes", value = T))
        ),
        DT::dataTableOutput("deseq_result_tbl"),
        uiOutput("download_deseq_result_ui"),
        hr(),
        uiOutput("deseq_sig_genes")
    )
})

output$deseq_sig_genes <- renderUI({
    req(r_data$deseq_results)
    sm <- capture.output(DESeq2::summary.DESeqResults(r_data$deseq_results))
    list(
        tags$h4("Summary"),
        tags$li(paste0("Total number of significant genes: ", sum(r_data$deseq_results$padj < input$deseq_alpha, na.rm = T), ".")),
        tags$li(sm[4]),
        tags$li(sm[5]),
        tags$li(sm[6]),
        tags$li(paste(sm[7], sm[8]))
    )
})

output$deseq_test_method_text <- renderUI({
    req(r_data$deseq_results)
    if(r_data$deseq_params$test == "Wald") {
        test_text1 <- r_data$deseq_results@elementMetadata$description[4]
        test_text2 <- "Note: The Wald p-value will be different for different pairwise comparisons / individual points."
    } else {
        test_text1 <- r_data$deseq_results@elementMetadata$description[4]
        test_text2 <- "Note: The LRT p-value does not depend on the group choice."
    }
    return(
        list(
            tags$li(test_text1),
            tags$li(test_text2)
        )
    )
})

output$download_deseq_result_ui <- renderUI({
    req(r_data$deseq_results)
    tbl<-as.data.frame(r_data$deseq_results)
    if(nrow(tbl) == 0) return()
    download_deseq_result_ui <- downloadButton("download_deseq_result","Download", class = "btn btn-success")
})

observe({
    req(r_data$meta, r_data$dds, r_data$deseq_params, ncol(r_data$meta) >= 2)

    req(input$deseq_result_name)
    result_name <- input$deseq_result_name

    withProgress(message = 'Processing...', value = 0.5, {
        res1 <- DESeq2::results(r_data$dds, test = r_data$deseq_params$test,
                                name = result_name,
                                alpha = input$deseq_alpha)

        r_data$deseq_results <- res1[order(res1$padj),]
        r_data$deseq_group <- input$deseq_result_name
    })
})

output$deseq_result_tbl <- DT::renderDataTable({
    req(r_data$deseq_results)
    if(input$deseq_cuttbl) {
        tbl<- as.data.frame(BiocGenerics::subset(r_data$deseq_results, padj <= input$deseq_alpha))
    } else {
        tbl<- as.data.frame(r_data$deseq_results)
    }
    if(nrow(tbl) == 0) return()
    DT::datatable(tbl, selection = 'single', options = list(scrollX = TRUE, scrollY = "250px", searching=T, order = list(list(6, 'asc')) , orderClasses = T))
})

output$download_deseq_result <- downloadHandler(
    filename = function() {
        "deseq_results.csv"
    },
    content = function(file) {
        if(input$deseq_cuttbl) {
            tbl<- as.data.frame(BiocGenerics::subset(r_data$deseq_results, padj <= input$deseq_alpha))
        } else {
            tbl<- as.data.frame(r_data$deseq_results)
        }
        if(nrow(tbl) == 0) return()
        write.csv(as.data.frame(tbl), file)
    }
)

output$deseq_ma_plt <- renderPlot({
    if(is.null(r_data$deseq_results)) return()
    BiocGenerics::plotMA(r_data$deseq_results, main="DESeq2", ylim=c(-2,2))
})

output$deseq_gene_plot_ui <- renderUI({
    req(r_data$deseq_params)
    pivot_featurePlot_UI("deseq_gene_plt", meta = r_data$meta)
})

observe({
    req(r_data$deseq_results, !is.null(input$deseq_cuttbl))
    s = input$deseq_result_tbl_row_last_clicked
    req(r_data$deseq_results)
    if(input$deseq_cuttbl) {
        tbl<- as.data.frame(BiocGenerics::subset(r_data$deseq_results, padj <= input$deseq_alpha))
    } else {
        tbl<- as.data.frame(r_data$deseq_results)
    }

    if (length(s)) {
        selected_gene <- rownames(tbl[s, , drop = FALSE])
    } else {
        return()
    }

    d <- as.data.frame(t(r_data$df[selected_gene,])) %>% tibble::rownames_to_column()
    colnames(d) <- c("sample", "expression_level")
    callModule(pivot_featurePlot, "deseq_gene_plt", meta = r_data$meta, df = d, gene = selected_gene)
})



