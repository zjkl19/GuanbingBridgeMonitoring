classdef StatsSchema
    %STATSSCHEMA Canonical stats fields, units and report precision.

    methods (Static)
        function schema = forModule(key)
            key = char(string(key));
            schema = struct('schema_version', 1, 'module', key, 'columns', {{}});
            switch key
                case 'temperature'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Min','C','min',1; 'Max','C','max',1; 'Mean','C','mean',1});
                case 'humidity'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Min','%','min',1; 'Max','%','max',1; 'Mean','%','mean',1});
                case 'rainfall'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Max_mm_h','mm/h','max',3; 'Total_mm','mm','sum',2});
                case 'deflection'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'OrigMin_mm','mm','min',1; 'OrigMax_mm','mm','max',1; 'FiltMin_mm','mm','min',1; 'FiltMax_mm','mm','max',1});
                case 'bearing_displacement'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'FiltMin_mm','mm','min',1; 'FiltMax_mm','mm','max',1});
                case 'tilt'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Min','deg','min',3; 'Max','deg','max',3});
                case {'strain','dynamic_strain_highpass','dynamic_strain_lowpass'}
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Min','ue','min',3; 'Max','ue','max',3; 'Mean','ue','mean',3});
                case 'crack'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'CrkMin','mm','min',3; 'CrkMax','mm','max',3; 'CrkMean','mm','mean',3});
                case {'acceleration','cable_accel'}
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Min','m/s^2','min',3; 'Max','m/s^2','max',3; 'RMS10minMax','m/s^2','max',3});
                case 'gnss'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Component','','component',NaN; 'Min_mm','mm','min',1; 'Max_mm','mm','max',1});
                case 'wind'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Mean10minMax','m/s','max',2; 'MeanSpeed','m/s','mean',2; 'MaxSpeed','m/s','max',2});
                case 'earthquake'
                    schema.columns = bms.io.StatsSchema.columns({'PointID','','id',NaN; 'Component','','component',NaN; 'Peak','m/s^2','max',3; 'PeakTime','','time',NaN});
            end
        end

        function cols = columns(raw)
            cols = struct('name', {}, 'unit', {}, 'role', {}, 'decimals', {});
            for i = 1:size(raw, 1)
                cols(end+1) = struct( ...
                    'name', char(string(raw{i,1})), ...
                    'unit', char(string(raw{i,2})), ...
                    'role', char(string(raw{i,3})), ...
                    'decimals', raw{i,4}); %#ok<AGROW>
            end
        end

        function digits = decimalsFor(schemaOrKey, columnName, fallback)
            if nargin < 3, fallback = NaN; end
            if ischar(schemaOrKey) || isstring(schemaOrKey)
                schema = bms.io.StatsSchema.forModule(schemaOrKey);
            else
                schema = schemaOrKey;
            end
            digits = fallback;
            if ~isstruct(schema) || ~isfield(schema, 'columns'), return; end
            cols = bms.app.ManifestReader.recordsToCell(schema.columns);
            for i = 1:numel(cols)
                col = cols{i};
                if isstruct(col) && isfield(col, 'name') && strcmp(char(string(col.name)), char(string(columnName)))
                    if isfield(col, 'decimals') && ~isempty(col.decimals)
                        digits = col.decimals;
                    end
                    return;
                end
            end
        end

        function T = normalizeTable(T, key)
            schema = bms.io.StatsSchema.forModule(key);
            cols = bms.app.ManifestReader.recordsToCell(schema.columns);
            for i = 1:numel(cols)
                col = cols{i};
                if ~isstruct(col) || ~isfield(col, 'name') || ~isfield(col, 'decimals')
                    continue;
                end
                name = char(string(col.name));
                digits = col.decimals;
                if isnan(digits) || ~ismember(name, T.Properties.VariableNames) || ~isnumeric(T.(name))
                    continue;
                end
                T.(name) = round(T.(name), digits);
            end
        end

        function s = registry()
            specs = bms.module.ModuleRegistry.forCategory('analysis');
            s = struct('schema_version', 1, 'modules', {{}});
            for i = 1:numel(specs)
                if isempty(specs(i).StatsFile), continue; end
                s.modules{end+1} = bms.io.StatsSchema.forModule(specs(i).Key); %#ok<AGROW>
            end
        end
    end
end
