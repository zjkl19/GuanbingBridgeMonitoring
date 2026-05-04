classdef StepDefinition
    %STEPDEFINITION Metadata for one legacy analysis step.

    properties
        Key char = ''
        OptField char = ''
        Label char = ''
        StatsFile char = ''
        Category char = 'analysis'
    end

    methods
        function obj = StepDefinition(key, optField, label, statsFile, category)
            if nargin >= 1, obj.Key = char(key); end
            if nargin >= 2, obj.OptField = char(optField); end
            if nargin >= 3, obj.Label = char(label); end
            if nargin >= 4, obj.StatsFile = char(statsFile); end
            if nargin >= 5, obj.Category = char(category); end
        end

        function s = toStruct(obj, statsDir)
            if nargin < 2, statsDir = ''; end
            s = struct();
            s.key = obj.Key;
            s.opt_field = obj.OptField;
            s.label = obj.Label;
            s.category = obj.Category;
            s.stats_file = obj.StatsFile;
            s.stats_path = '';
            if ~isempty(statsDir) && ~isempty(obj.StatsFile)
                s.stats_path = fullfile(statsDir, obj.StatsFile);
            end
        end
    end

    methods (Static)
        function defs = catalog()
            defs = [ ...
                bms.app.StepDefinition('zip_precheck','precheck_zip_count',char([39044 26816 26597 21387 32553 21253 25968 37327]),'', 'preprocess'), ...
                bms.app.StepDefinition('unzip','doUnzip',char([25209 37327 35299 21387]),'', 'preprocess'), ...
                bms.app.StepDefinition('rename_csv','doRenameCsv',char([25209 37327 37325 21629 21517 67 83 86]),'', 'preprocess'), ...
                bms.app.StepDefinition('remove_header','doRemoveHeader',char([25209 37327 21435 38500 34920 22836]),'', 'preprocess'), ...
                bms.app.StepDefinition('resample','doResample',char([25209 37327 37325 37319 26679]),'', 'preprocess'), ...
                bms.app.StepDefinition('temperature','doTemp',char([28201 24230 20998 26512]),'temp_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('humidity','doHumidity',char([28287 24230 20998 26512]),'humidity_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('rainfall','doRainfall',char([38632 37327 20998 26512]),'rainfall_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('gnss','doGNSS',char([71 78 83 83 20998 26512]),'gnss_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('wind','doWind',char([39118 36895 39118 21521 20998 26512]),'wind_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('earthquake','doEq',char([22320 38663 21160 20998 26512]),'eq_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('wim','doWIM',char([87 73 77]),'', 'analysis'), ...
                bms.app.StepDefinition('deflection','doDeflect',char([25376 24230 20998 26512]),'deflection_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('bearing_displacement','doBearingDisplacement',char([25903 24231 20301 31227 20998 26512]),'bearing_displacement_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('tilt','doTilt',char([20542 35282 20998 26512]),'tilt_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('acceleration','doAccel',char([21152 36895 24230 20998 26512]),'accel_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('cable_accel','doCableAccel',char([32034 21147 21152 36895 24230 20998 26512]),'cable_accel_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('accel_spectrum','doAccelSpectrum',char([21152 36895 24230 39057 35889]),'accel_spec_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('cable_accel_spectrum','doCableAccelSpectrum',char([32034 21147 21152 36895 24230 39057 35889]),'cable_accel_spec_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('rename_crk','doRenameCrk',char([35010 32541 37325 21629 21517]),'', 'preprocess'), ...
                bms.app.StepDefinition('crack','doCrack',char([35010 32541 20998 26512]),'crack_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('strain','doStrain',char([24212 21464 20998 26512]),'strain_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('dynamic_strain_highpass','doDynStrainBoxplot',char([21160 24212 21464 20998 26512 65288 39640 36890 43 21547 31665 32447 22270 65289]),'dynamic_strain_highpass_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('dynamic_strain_lowpass','doDynStrainLowpassBoxplot',char([21160 24212 21464 20998 26512 65288 20302 36890 43 21547 31665 32447 22270 65289]),'dynamic_strain_lowpass_stats.xlsx', 'analysis'), ...
                bms.app.StepDefinition('offset_correction_report','', 'offset_correction_report','', 'postprocess') ...
                ];
        end

        function def = fromLabel(label)
            label = char(label);
            defs = bms.app.StepDefinition.catalog();
            def = bms.app.StepDefinition('', '', label, '', 'analysis');
            for i = 1:numel(defs)
                if strcmp(defs(i).Label, label)
                    def = defs(i);
                    return;
                end
            end
        end

        function def = fromKey(key)
            key = char(key);
            defs = bms.app.StepDefinition.catalog();
            def = bms.app.StepDefinition(key, '', key, '', 'analysis');
            for i = 1:numel(defs)
                if strcmp(defs(i).Key, key)
                    def = defs(i);
                    return;
                end
            end
        end

        function defs = enabledFromOptions(opts)
            all = bms.app.StepDefinition.catalog();
            defs = bms.app.StepDefinition.empty();
            for i = 1:numel(all)
                opt = all(i).OptField;
                if isempty(opt), continue; end
                if isfield(opts, opt) && logical(opts.(opt))
                    defs(end+1) = all(i); %#ok<AGROW>
                end
            end
        end
    end
end
