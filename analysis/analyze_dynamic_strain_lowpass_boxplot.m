function analyze_dynamic_strain_lowpass_boxplot(root_dir, start_date, end_date, varargin)
%ANALYZE_DYNAMIC_STRAIN_LOWPASS_BOXPLOT Compatibility wrapper for lowpass dynamic strain boxplots.

    bms.analyzer.DynamicStrainBoxplotPipeline.run('lowpass', root_dir, start_date, end_date, varargin{:});
end
