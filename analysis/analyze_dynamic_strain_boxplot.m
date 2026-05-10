function analyze_dynamic_strain_boxplot(root_dir, start_date, end_date, varargin)
%ANALYZE_DYNAMIC_STRAIN_BOXPLOT Compatibility wrapper for highpass dynamic strain boxplots.

    bms.analyzer.DynamicStrainBoxplotPipeline.run('highpass', root_dir, start_date, end_date, varargin{:});
end
