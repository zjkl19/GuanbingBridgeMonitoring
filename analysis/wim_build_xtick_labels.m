function labels = wim_build_xtick_labels(xlabels, yvals, show_pct, percent_on_newline)
% wim_build_xtick_labels  Compatibility wrapper for WIM plot tick labels.

    labels = bms.analyzer.WimPlotService.buildXTickLabels(xlabels, yvals, show_pct, percent_on_newline);
end
