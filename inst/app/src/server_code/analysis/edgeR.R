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


output$edgeR_ui <- renderUI({
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
            title = "edgeR Differential Expression Analysis",
            id = "edgeR",
            status = "primary",
            solidHeader = T,
            collapsible = T,
            reportable = T,
            get_html = T,
            register_analysis= T,
            tags$div(tags$b("Modeling Settings:"), class = "param_setting_title"),
            fluidRow(
                column(3,
                       selectInput("edgeR_norm_method", "Data normalization method", choices = list(
                           "Trimmed Mean of M-values (TMM)" = "TMM",
                           "RLE(DESeq)" = "RLE",
                           "Upperquartile" = "upperquartile",
                           "None" = "none"
                       ), selected = "TMM"),
                       tags$p("Your raw data will be re-normalized with the above edgeR preferred methods.")
                ),
                pivot_deGroupBy_UI("edgeR", r_data$meta, width = 9, reduced = "no", model = c("condition", "condition_batch", "custom"))
            ),
            fluidRow(
                column(3,
                       selectInput("edgeR_test_method", "Test Method", choices = list("Exact test" = "exact", "GLM likelihood ratio test" = "glm", "GLM quasi-likelihood F-test" = "glmQL"), selected = "exact")
                ),
                column(9,
                       uiOutput("edgeR_test_explain")
                )
            ),
            fluidRow(
                column(9),
                column(3, actionButton("perform_edgeR", "Run Modeling", class = "btn-info"))
            )
        ),
        uiOutput("edgeR_results_box"),
        box(
            width = 12,
            title = "Citation",
            status = "primary",
            tags$ol(
                tags$li("Robinson MD, McCarthy DJ and Smyth GK (2010). edgeR: a Bioconductor package for differential expression analysis of digital
  gene expression data. Bioinformatics 26, 139-140.", class = "citation"),
                tags$li("McCarthy DJ, Chen Y and Smyth GK (2012). Differential expression analysis of multifactor RNA-Seq experiments with respect to
  biological variation. Nucleic Acids Research 40, 4288-4297.")
            )
        )
    )

})


edgeRModel <- callModule(pivot_deGroupBy, "edgeR", meta = r_data$meta, reduced = "no")


output$edgeR_test_explain <- renderUI({
    req(input$edgeR_test_method)
    if(input$edgeR_test_method == "exact") {
        list(
            tags$b("Exact Tests for Differences between Two Groups of Negative-Binomial Counts: "),
            tags$li("Implement the exact test proposed by Robinson and Smyth (2008) for a difference in mean between two groups of negative binomial random variables."),
            tags$li("Note: Can only be applied when condition is the single factor.")
        )
    } else if(input$edgeR_test_method == "glm") {
        list(
            tags$b("Genewise Negative Binomial Generalized Linear Models: "),
            tags$li("Implement generalized linear model (glm) methods developed by McCarthy et al (2012)."),
            tags$li("Function name: glmFit and glmLRT. See edgeR users guide section 3.2.3 for more details.")
            )
    } else if(input$edgeR_test_method == "glmQL") {
        list(
            tags$b("Genewise Negative Binomial Generalized Linear Models with Quasi-likelihood Tests: "),
            tags$li("Implement the quasi-likelihood (QL) methods of Lund et al (2012), is similar to glmLRT except that it replaces likelihood ratio tests with empirical Bayes quasi-likelihood F-tests."),
            tags$li("Function name: glmQLFit and glmQLFTest. See edgeR users guide section 3.2.3 for more details.")
        )
    } else {
        return()
    }
})

observeEvent(input$perform_edgeR, {
    req(r_data$meta, edgeRModel(), input$edgeR_norm_method, input$edgeR_test_method, ncol(r_data$meta) >= 2)

    # Clear previous results if exist
    if(!is.null(r_data$edgeR)) {
        r_data$edgeR <- NULL
        r_data$edgeR_params <- NULL
        r_data$edgeR_group <- NULL
        r_data$edgeR_fit <- NULL
        r_data$edgeR_test <- NULL
        r_data$edgeR_results <- NULL
    }

    if(input$edgeR_test_method == "exact") {
        if(edgeRModel()$design != "condition") {
            session$sendCustomMessage(type = "showalert", "Exact test can only be applied to design '~condition'.")
            return()
        }
        condVar <- all.vars(edgeRModel()$model$full)
        groups = r_data$meta[,condVar]
    } else {
        groups = NULL
    }

    withProgress(message = 'Processing...', value = 0.5, {
        error_I <- 0
        tryCatch({
            y <- edgeR::DGEList(counts=r_data$raw, group=groups)
            y <- edgeR::calcNormFactors(y, method = input$edgeR_norm_method)
            design <- model.matrix(edgeRModel()$model$full, data = r_data$meta)
            y <- edgeR::estimateDisp(y,design)
            if(input$edgeR_test_method == "glm") {
                fit <- edgeR::glmFit(y,design)
            } else if (input$edgeR_test_method == "glmQL") {
                fit <- edgeR::glmQLFit(y,design)
            } else {
                fit <- NULL
            }
        },
        error = function(e){
            error_I <<- 1
        }
        )

        if(error_I) {
            session$sendCustomMessage(type = "showalert", "edgeR modeling failed.")
            return()
        }
        r_data$edgeR <- y
        r_data$edgeR_fit <- fit
        r_data$edgeR_group <- NULL
        r_data$edgeR_params <- list(design = edgeRModel()$design, test = input$edgeR_test_method, model = edgeRModel()$model)
    })
})

output$edgeR_results_box <- renderUI({
    req(r_data$meta, ncol(r_data$meta) >= 2, r_data$edgeR)

    designVar <- all.vars(r_data$edgeR_params$model$full)
    cond <- designVar[1]

    if(r_data$edgeR_params$test == "exact") {
        options <- unique(r_data$meta[,cond])
        names(options) <- options
    }

    edgeR_group_ui <- list(
        if(r_data$edgeR_params$test == "exact") {
            fluidRow(
                column(4, tags$br(),tags$b("Contrast:")),
                column(4, selectInput("edgeR_term1", "Term 1", choices = as.list(options), selected = options[[1]])),
                column(4, selectInput("edgeR_term2", "Term 2", choices = as.list(options), selected = options[[2]]))
            )
        } else {
            list(
                fluidRow(
                    column(4, selectInput("edgeR_target", "Test coeffcient/contrast", choices = list("Coefficient" = "coef", "Contrast" = "contrast"), selected = "coef")),
                    column(8, uiOutput("edgeR_target_text"))
                ),
                uiOutput("edgeR_coef_ui")
            )
        }

    )

    enhanced_box(
        width = 12,
        title = NULL,
        status = "primary",
        solidHeader = T,
        tags$div(tags$b("Comparison Settings:"), pivot_help_UI("edgeR_compare", "How to compare your groups?"), class = "param_setting_title"),
        edgeR_group_ui,
        fluidRow(
            column(4,
                   selectInput("edgeR_p_method", "P adjustment method",
                               choices = list(
                                   "Bonferroni correction" = "bonferroni",
                                   "False discovery rate" = "fdr",
                                   "Holm (1979)" = "holm", "Hochberg (1988)" = "hochberg",
                                   "Hommel (1988)" = "hommel",
                                   "Benjamini & Yekutieli (2001)" = "BY",
                                   "None" = "none"), selected = "fdr")
            ),
            column(4, numericInput("edgeR_alpha", "FDR cutoff", value = 0.1, min = 0, max = 0.5, step = 0.001)),
            column(4, tags$br(), checkboxInput("edgeR_cuttbl", "Only show significant genes", value = T))
        ),
        hr(),
        fluidRow(
            column(6,
                   tags$div(tags$b("Results Table:"), class = "param_setting_title"),
                   uiOutput("edgeR_result_text"),
                   DT::dataTableOutput("edgeR_result_tbl"),
                   uiOutput("edgeR_sig_genes"),
                   downloadButton("download_edgeR_result","Download", class = "btn-success btn_rightAlign")
            ),
            column(6,
                   tags$div(tags$b("Mean-Difference Plot:"), class = "param_setting_title"),
                   fluidRow(
                       column(6, numericInput("edgeR_MD_fc", "Hightlight Fold Change", value = 1, min = 0, max = 10, step = 1)),
                       column(6, uiOutput("edgeR_MD_colui"))
                   ),
                   plotOutput("edgeR_MD")
            )
        ),
        pivot_featurePlot_UI("edgeR_gene", meta = r_data$meta)
    )
})

output$edgeR_target_text <- renderUI({
    req(input$edgeR_target)
    if(input$edgeR_target == "coef") {
        list(
            tags$br(),
            tags$li("Test if selected coefficients of the linear model are equal to zero, corresponding to the the coef argument of glmLRT or glmQLFTest function."),
            tags$li("Check all condition terms will test if there are any differences between the conditions, analogous to a one-way ANOVA test.")
        )
    } else {
        list(
            tags$br(),
            tags$li("Contrast of the coefficients of the linear model, corresponding to the contrast argument glmLRT or glmQLFTest function."),
            tags$li("For pairwise comparison not against baseline, just set the relavant terms to 1 and -1.")
        )
    }
})

output$edgeR_coef_ui <- renderUI({
    req(input$edgeR_target)
    options <-  colnames(r_data$edgeR_fit)
    options <- options[which(options != "(Intercept)")]
    names(options) <- options

    if(input$edgeR_target == "coef") {
        checkboxGroupInput("edgeR_coef", "Coefficients", choices = options, inline = T)
    } else {
        lapply(options, function(co) {inline(numericInput(paste0("edgeR_coef", co), co, value = 0, min = -1, max = 1, step = 0.5), width = "100px")})
    }
})

observe({
    req(r_data$edgeR, r_data$edgeR_params, input$edgeR_p_method, input$edgeR_alpha)

    if(r_data$edgeR_params$test == "exact") {
        req(input$edgeR_term1, input$edgeR_term1 != input$edgeR_term2)
    } else {
        req(input$edgeR_target)
    }
    withProgress(message = 'Processing...', value = 0.5, {
        error_I <- 0
        tryCatch({
            if(r_data$edgeR_params$test == "exact") {
                et <- edgeR::exactTest(r_data$edgeR, pair = c(input$edgeR_term1, input$edgeR_term2))
            } else {
                if(input$edgeR_target == "coef") {
                    if(is.null(input$edgeR_coef)) return()
                    if(r_data$edgeR_params$test == "glm") {
                        et <- edgeR::glmLRT(r_data$edgeR_fit, coef=input$edgeR_coef)
                    } else if(r_data$edgeR_params$test == "glmQL") {
                        et <- edgeR::glmQLFTest(r_data$edgeR_fit, coef=input$edgeR_coef)
                    }
                } else {
                    options <- colnames(r_data$edgeR_fit)
                    options <- options[which(options != "(Intercept)")]
                    names(options) <- options
                    vals<-unlist(lapply(options, function(co) {input[[paste0("edgeR_coef", co)]]}))
                    if("(Intercept)" %in%  colnames(r_data$edgeR_fit)) {
                        vals <- c(0, vals)
                    }
                    if(any(is.na(vals))) return()
                    if(all(vals == 0)) return()
                    if(r_data$edgeR_params$test == "glm") {
                        et <- edgeR::glmLRT(r_data$edgeR_fit, contrast=vals)
                    } else if(r_data$edgeR_params$test == "glmQL") {
                        et <- edgeR::glmQLFTest(r_data$edgeR_fit, contrast = vals)
                    }
                }
            }},
            error = function(e){
                error_I <<- 1
            }
        )

        if(error_I) {
            session$sendCustomMessage(type = "showalert", "edgeR DE failed.")
            return()
        }
        r_data$edgeR_test <- et
        r_data$edgeR_results <- edgeR::topTags(et, n = nrow(r_data$raw),
                                        adjust.method = input$edgeR_p_method,
                                        p.value = ifelse(input$edgeR_cuttbl, input$edgeR_alpha, 1))
    })
})

output$edgeR_result_text <- renderUI({
    req(r_data$edgeR_results)
    text = paste0(r_data$edgeR_results$test, " test: ", paste0(r_data$edgeR_results$comparison, collapse = ", "))
    div(tags$b(text), class = "table-cap")
})

output$edgeR_result_tbl <- DT::renderDataTable({
    req(r_data$edgeR_results)
    tbl<-as.data.frame(r_data$edgeR_results$table)
    if(nrow(tbl) == 0) return()
    DT::datatable(tbl, selection = 'single', options = list(scrollX = TRUE, scrollY = "250px", searching=T))
})

output$download_edgeR_result <- downloadHandler(
    filename = function() {
        "edgeR_results.csv"
    },
    content = function(file) {
        tbl<-as.data.frame(r_data$edgeR_results$table)
        write.csv(tbl, file)
    }
)

output$edgeR_sig_genes <- renderUI({
    req(r_data$edgeR_results)
    error_I <- 0
    tryCatch({
        gstatus<-edgeR::decideTestsDGE(r_data$edgeR_test, adjust.method = input$edgeR_p_method,
                                p.value = input$edgeR_alpha)
    }, error = function(e) {
        error_I <<- 1
    })
    if(error_I) return()

    up <- sum(gstatus > 0)
    down <- sum(gstatus < 0)
    list(
        tags$li(paste0("Total number of significant genes: ", nrow(r_data$edgeR_results), ".")),
        tags$li(paste0("Up-regulation: ", up, ".")),
        tags$li(paste0("Down-regulation: ", down, "."))
    )
})


output$edgeR_MD <- renderPlot({
    req(r_data$edgeR_test)
    error_I <- 0
    tryCatch({
        limma::plotMD(r_data$edgeR_test, status = edgeR::decideTestsDGE(r_data$edgeR_test, adjust.method = input$edgeR_p_method,
                                                                 p.value = input$edgeR_alpha))
    }, error = function(e) {
        error_I <<- 1
    })
    if(error_I) return()

    if(input$edgeR_MD_fc) {
        abline(h=c(-input$edgeR_MD_fc,input$edgeR_MD_fc), col="blue")
    }
})


observe({
    req(r_data$edgeR, r_data$edgeR_results)
    s = input$edgeR_result_tbl_row_last_clicked
    tbl<-r_data$edgeR_results$table
    if (length(s)) {
        selected_gene <- rownames(tbl[s, , drop = FALSE])
    } else {
        return()
    }

    df <- as.data.frame(edgeR::cpm(r_data$edgeR, normalized.lib.sizes=TRUE))

    d <- as.data.frame(t(df[selected_gene,])) %>% tibble::rownames_to_column()
    if(ncol(d) != 2) return()
    colnames(d) <- c("sample", "expression_level")

    callModule(pivot_featurePlot, "edgeR_gene", meta = r_data$meta, df = d, gene = selected_gene)
})

#
#
