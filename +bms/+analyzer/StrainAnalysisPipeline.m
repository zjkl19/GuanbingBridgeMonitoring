classdef StrainAnalysisPipeline
    %STRAINANALYSISPIPELINE Static strain stats, time series, and boxplots.

    methods (Static)
        function run(rootDir, startDate, endDate, excelFile, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(startDate), error('start_date is required'); end
            if nargin < 3 || isempty(endDate), error('end_date is required'); end
            if nargin < 4 || isempty(excelFile), excelFile = 'strain_stats.xlsx'; end
            if nargin < 6 || isempty(cfg), cfg = load_config(); end
            if nargin < 5 || isempty(subfolder)
                subfolder = bms.analyzer.StrainAnalysisPipeline.resolveSubfolder(cfg);
            end

            rootDir = char(string(rootDir));
            subfolder = char(string(subfolder));
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            ctx = bms.analyzer.StrainAnalysisPipeline.context(cfg);

            statsRows = cell(0, 4);
            if ctx.explicit_points
                statsRows = bms.analyzer.StrainAnalysisPipeline.runPoints( ...
                    rootDir, subfolder, startDate, endDate, cfg, ctx, statsRows);
            end

            if ctx.explicit_ts_groups
                [statsRows, ~] = bms.analyzer.StrainAnalysisPipeline.runTimeseriesGroups( ...
                    rootDir, subfolder, startDate, endDate, cfg, ctx, statsRows);
            end

            if ctx.explicit_groups
                [statsRows, ~] = bms.analyzer.StrainAnalysisPipeline.runBoxplotGroups( ...
                    rootDir, subfolder, startDate, endDate, cfg, ctx, statsRows);
            end

            T = bms.analyzer.StructuralSeriesService.basicStatsTable(statsRows);
            bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, 'strain');
            fprintf('Strain stats saved to %s\n', excelFile);
        end

        function subfolder = resolveSubfolder(varargin)
            subfolder = bms.analyzer.StrainConfigService.resolveSubfolder(varargin{:});
        end

        function ctx = context(varargin)
            ctx = bms.analyzer.StrainConfigService.context(varargin{:});
        end

        function rows = runPoints(varargin)
            rows = bms.analyzer.StrainSeriesService.runPoints(varargin{:});
        end

        function [rows, plottedGroups] = runTimeseriesGroups(varargin)
            [rows, plottedGroups] = bms.analyzer.StrainSeriesService.runTimeseriesGroups(varargin{:});
        end

        function [rows, plottedGroups] = runBoxplotGroups(varargin)
            [rows, plottedGroups] = bms.analyzer.StrainSeriesService.runBoxplotGroups(varargin{:});
        end

        function [dataList, statsRows] = collectGroupData(varargin)
            [dataList, statsRows] = bms.analyzer.StrainSeriesService.collectGroupData(varargin{:});
        end

        function plotPointCurve(varargin)
            bms.analyzer.StrainPlotService.plotPointCurve(varargin{:});
        end

        function plotGroupTimeseries(varargin)
            bms.analyzer.StrainPlotService.plotGroupTimeseries(varargin{:});
        end

        function plotGroupBoxplot(varargin)
            bms.analyzer.StrainPlotService.plotGroupBoxplot(varargin{:});
        end

        function dataMat = buildBoxplotMatrix(varargin)
            dataMat = bms.analyzer.StrainPlotService.buildBoxplotMatrix(varargin{:});
        end

        function drawBoxplotWarnLines(varargin)
            bms.analyzer.StrainPlotService.drawBoxplotWarnLines(varargin{:});
        end

        function warnLines = resolveWarnLines(varargin)
            warnLines = bms.analyzer.StrainConfigService.resolveWarnLines(varargin{:});
        end

        function groups = groups(varargin)
            groups = bms.analyzer.StrainConfigService.groups(varargin{:});
        end

        function groups = normalizeGroupMap(varargin)
            groups = bms.analyzer.StrainConfigService.normalizeGroupMap(varargin{:});
        end

        function tf = hasGroups(varargin)
            tf = bms.analyzer.StrainConfigService.hasGroups(varargin{:});
        end

        function groups = legacyGroups(varargin)
            groups = bms.analyzer.StrainConfigService.legacyGroups(varargin{:});
        end

        function points = resolvePoints(varargin)
            points = bms.analyzer.StrainConfigService.resolvePoints(varargin{:});
        end

        function style = style(varargin)
            style = bms.analyzer.StrainConfigService.style(varargin{:});
        end

        function value = styleField(varargin)
            value = bms.analyzer.StrainConfigService.styleField(varargin{:});
        end

        function y = pointYLim(varargin)
            y = bms.analyzer.StrainConfigService.pointYLim(varargin{:});
        end

        function y = groupYLim(varargin)
            y = bms.analyzer.StrainConfigService.groupYLim(varargin{:});
        end

        function out = sanitizeFilename(varargin)
            out = bms.analyzer.StrainConfigService.sanitizeFilename(varargin{:});
        end

        function colors = defaultGroupColors(varargin)
            colors = bms.analyzer.StrainConfigService.defaultGroupColors(varargin{:});
        end

        function colors = groupColors(varargin)
            colors = bms.analyzer.StrainConfigService.groupColors(varargin{:});
        end

        function tf = truthy(varargin)
            tf = bms.analyzer.StrainConfigService.truthy(varargin{:});
        end
    end
end
