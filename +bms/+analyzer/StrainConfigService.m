classdef StrainConfigService
    %STRAINCONFIGSERVICE Configuration helpers for strain analysis.

    methods (Static)
        function subfolder = resolveSubfolder(cfg)
            subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'strain', '特征值');
        end

        function ctx = context(cfg)
            ctx = struct();
            ctx.style = bms.analyzer.StrainConfigService.style(cfg);
            ctx.points = bms.analyzer.StrainConfigService.resolvePoints(cfg);
            ctx.groups = bms.analyzer.StrainConfigService.groups(cfg, 'strain');
            ctx.ts_groups = bms.analyzer.StrainConfigService.groups(cfg, 'strain_timeseries');
            ctx.explicit_points = ~isempty(ctx.points);
            ctx.explicit_groups = bms.analyzer.StrainConfigService.hasGroups(ctx.groups);
            ctx.explicit_ts_groups = bms.analyzer.StrainConfigService.hasGroups(ctx.ts_groups);

            if ~ctx.explicit_ts_groups && ctx.explicit_groups
                ctx.ts_groups = ctx.groups;
                ctx.explicit_ts_groups = true;
            end

            if ~ctx.explicit_points && ~ctx.explicit_groups && ~ctx.explicit_ts_groups
                ctx.groups = bms.analyzer.StrainConfigService.legacyGroups();
                ctx.ts_groups = ctx.groups;
                ctx.explicit_groups = true;
                ctx.explicit_ts_groups = true;
            end
        end

        function warnLines = resolveWarnLines(style, cfg, pointId)
            warnLines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, 'strain', pointId);
        end

        function groups = groups(cfg, key)
            groups = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, key, []);
        end

        function groups = normalizeGroupMap(groupsCfg)
            groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
        end

        function tf = hasGroups(groupsCfg)
            tf = bms.analyzer.StructuralPlotConfigService.hasGroups(groupsCfg);
        end

        function groups = legacyGroups()
            groups = struct( ...
                'G05', {{'GB-RSG-G05-001-01', 'GB-RSG-G05-001-02', 'GB-RSG-G05-001-03', 'GB-RSG-G05-001-04', 'GB-RSG-G05-001-05', 'GB-RSG-G05-001-06'}}, ...
                'G06', {{'GB-RSG-G06-001-01', 'GB-RSG-G06-001-02', 'GB-RSG-G06-001-03', 'GB-RSG-G06-001-04', 'GB-RSG-G06-001-05', 'GB-RSG-G06-001-06'}}); %#ok<STRNU>
        end

        function points = resolvePoints(cfg)
            points = bms.analyzer.StructuralPlotConfigService.getPoints(cfg, 'strain', {});
        end

        function style = style(cfg)
            style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, 'strain');
        end

        function value = styleField(style, field, defaultValue)
            value = bms.analyzer.StructuralPlotConfigService.getStyleField(style, field, defaultValue);
        end

        function y = pointYLim(style, pointId, defaultValue)
            y = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, pointId, defaultValue);
        end

        function y = groupYLim(style, groupName, defaultValue)
            y = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, groupName, defaultValue);
        end

        function out = sanitizeFilename(name)
            out = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(name);
        end

        function colors = defaultGroupColors()
            colors = [
                0.0000 0.4470 0.7410
                0.8500 0.3250 0.0980
                0.9290 0.6940 0.1250
                0.4940 0.1840 0.5560
                0.4660 0.6740 0.1880
                0.3010 0.7450 0.9330
            ];
        end

        function colors = groupColors(style, nSeries)
            colors = bms.analyzer.StructuralPlotConfigService.groupColors( ...
                style, nSeries, 'colors_6', bms.analyzer.StrainConfigService.defaultGroupColors());
        end

        function tf = truthy(value)
            tf = bms.config.ConfigReader.boolValue(value, false);
        end
    end
end
