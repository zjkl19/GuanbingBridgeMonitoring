classdef LegacyStepFunctions
    %LEGACYSTEPFUNCTIONS Shared helpers used while migrating run_all.

    methods (Static)
        function sub = buildSubfolders(cfg)
            sub = struct();
            valueFeature = char([29305 24449 20540]);
            waveform = char([27874 24418]);
            featureResampled = [valueFeature '_' char([37325 37319 26679])];
            waveformResampled = [waveform '_' char([37325 37319 26679])];
            cableAccel = char([32034 21147 21152 36895 24230]);
            sub.temperature  = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'temperature',  valueFeature);
            sub.humidity     = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'humidity',     valueFeature);
            sub.rainfall     = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'rainfall',     valueFeature);
            sub.gnss         = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'gnss',         waveform);
            sub.deflection   = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'deflection',   featureResampled);
            sub.bearing_displacement = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'bearing_displacement', sub.deflection);
            sub.tilt         = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'tilt',         waveformResampled);
            sub.accel        = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'acceleration', waveformResampled);
            sub.accel_raw    = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'acceleration_raw', waveform);
            sub.cable_accel  = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'cable_accel', [cableAccel '_' char([37325 37319 26679])]);
            sub.cable_accel_raw = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'cable_accel_raw', cableAccel);
            sub.crack        = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'crack',        valueFeature);
            sub.strain       = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'strain',       valueFeature);
            sub.wind_raw     = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'wind_raw',     waveform);
            sub.eq_raw       = bms.app.LegacyStepFunctions.getSubfolder(cfg, 'eq_raw',       waveform);
        end

        function sub = getSubfolder(cfg, key, fallback)
            sub = fallback;
            if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, key)
                sub = cfg.subfolders.(key);
            end
        end

        function tf = isEnabled(opts, field)
            tf = isfield(opts, field) && logical(opts.(field));
        end

        function pts = getPoints(cfg, key, fallback)
            pts = bms.app.LegacyStepFunctions.normalizePoints(fallback);
            if isfield(cfg, 'points') && isfield(cfg.points, key)
                raw = cfg.points.(key);
                if isempty(raw)
                    pts = {};
                    return;
                end
                if iscell(raw) || isstring(raw) || ischar(raw)
                    pts = bms.app.LegacyStepFunctions.normalizePoints(raw);
                end
            end
        end

        function pts = getSensorPoints(cfg, key, fallback)
            pts = bms.app.LegacyStepFunctions.getPoints(cfg, key, fallback);
            if strcmpi(key, 'temperature') || strcmpi(key, 'humidity')
                shared = bms.app.LegacyStepFunctions.getPoints(cfg, 'temp_humidity', {});
                pts = bms.app.LegacyStepFunctions.mergePointLists(pts, shared);
            end
        end

        function pts = mergePointLists(a, b)
            pts = [bms.app.LegacyStepFunctions.normalizePoints(a); bms.app.LegacyStepFunctions.normalizePoints(b)];
            if isempty(pts)
                return;
            end
            pts = unique(pts, 'stable');
        end

        function pts = normalizePoints(v)
            pts = {};
            if isstring(v)
                pts = cellstr(v(:));
            elseif ischar(v)
                vv = strtrim(v);
                if ~isempty(vv)
                    pts = {vv};
                end
            elseif iscell(v)
                tmp = {};
                for i = 1:numel(v)
                    item = v{i};
                    if isstring(item)
                        if isscalar(item)
                            item = char(item);
                        else
                            continue;
                        end
                    end
                    if ischar(item)
                        item = strtrim(item);
                        if ~isempty(item)
                            tmp{end+1,1} = item; %#ok<AGROW>
                        end
                    end
                end
                pts = tmp;
            end
        end

        function [freqs, tol] = getAccelSpecParams(cfg)
            freqs = [1.150 1.480 2.310];
            tol   = 0.15;
            if isfield(cfg,'accel_spectrum_params') && isstruct(cfg.accel_spectrum_params)
                ps = cfg.accel_spectrum_params;
                if isfield(ps,'target_freqs') && ~isempty(ps.target_freqs), freqs = ps.target_freqs; end
                if isfield(ps,'tolerance')   && ~isempty(ps.tolerance),    tol   = ps.tolerance;   end
                if isfield(ps,'peak_orders') && ~isempty(ps.peak_orders)
                    [ok, freqs2, tol2] = bms.analyzer.SpectrumConfigService.peakOrdersToParams(ps.peak_orders, freqs, tol, [], {}, {});
                    if ok
                        freqs = freqs2;
                        tol = tol2;
                    end
                end
            end
        end

        function [freqs, tol] = getCableSpecParams(cfg)
            freqs = [1.150 1.480 2.310];
            tol   = 0.15;
            if isfield(cfg,'cable_accel_spectrum_params') && isstruct(cfg.cable_accel_spectrum_params)
                ps = cfg.cable_accel_spectrum_params;
                if isfield(ps,'target_freqs') && ~isempty(ps.target_freqs), freqs = ps.target_freqs; end
                if isfield(ps,'tolerance')   && ~isempty(ps.tolerance),    tol   = ps.tolerance;   end
                if isfield(ps,'peak_orders') && ~isempty(ps.peak_orders)
                    [ok, freqs2, tol2] = bms.analyzer.SpectrumConfigService.peakOrdersToParams(ps.peak_orders, freqs, tol, [], {}, {});
                    if ok
                        freqs = freqs2;
                        tol = tol2;
                    end
                end
            end
        end

        function name = dynamicHighpassOutputDir()
            name = [char([21160 24212 21464 31665 32447 22270]) '_' char([39640 36890 28388 27874])];
        end

        function pc = extractPlotCommon(cfg)
            pc = struct();
            if ~isstruct(cfg)
                return;
            end
            if isfield(cfg,'plot_common') && isstruct(cfg.plot_common)
                src = cfg.plot_common;
                if isfield(src,'save_fig'), pc.save_fig = src.save_fig; end
                if isfield(src,'lightweight_fig'), pc.lightweight_fig = src.lightweight_fig; end
                if isfield(src,'fig_max_points'), pc.fig_max_points = src.fig_max_points; end
                if isfield(src,'append_timestamp'), pc.append_timestamp = src.append_timestamp; end
                if isfield(src,'gap_mode'), pc.gap_mode = src.gap_mode; end
                if isfield(src,'gap_break_factor'), pc.gap_break_factor = src.gap_break_factor; end
                if isfield(src,'dynamic_raw_sampling_mode')
                    pc.dynamic_raw_sampling_mode = src.dynamic_raw_sampling_mode;
                end
            end
        end
    end
end
