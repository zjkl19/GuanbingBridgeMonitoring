classdef ModuleConfigRegistry
    %MODULECONFIGREGISTRY Metadata for config keys used by analysis modules.

    methods (Static)
        function specs = catalog()
            specs = [ ...
                bms.config.ModuleConfigRegistry.make('temperature', '温度', 'temperature', '', 'temperature', 'temperature', '', '', 'temperature', {'temperature', 'temp_humidity'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('humidity', '湿度', 'humidity', '', 'humidity', 'humidity', '', '', 'humidity', {'humidity', 'temp_humidity'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('rainfall', '雨量', 'rainfall', '', 'rainfall', 'rainfall', '', '', 'rainfall', {'rainfall'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('wind_speed', '风速', 'wind', 'speed', 'wind', 'wind_speed', 'wind', '', 'wind_raw', {'wind', 'wind_speed', 'wind_direction', 'wind_raw'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('wind_direction', '风向', 'wind', 'direction', 'wind', 'wind_direction', 'wind', '', 'wind_raw', {'wind', 'wind_speed', 'wind_direction', 'wind_raw'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('wind_speed10', '10min风速', 'wind', 'speed10', 'wind', 'wind_speed', 'wind', 'wind_params', 'wind_raw', {'wind', 'wind_speed', 'wind_raw'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('wind_rose', '风玫瑰', 'wind', 'rose', 'wind', 'wind_speed', 'wind', 'wind_params', 'wind_raw', {'wind', 'wind_speed', 'wind_direction', 'wind_raw'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('earthquake', '地震动', 'eq', '', 'eq', 'eq', '', 'eq_params', 'eq_raw', {'eq', 'eq_raw', 'earthquake'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('deflection', '挠度', 'deflection', '', 'deflection', 'deflection', 'deflection', '', 'deflection', {'deflection'}, {'warn_lines', 'group_warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('bearing_displacement', '支座/伸缩缝位移', 'bearing_displacement', '', 'bearing_displacement', 'bearing_displacement', 'bearing_displacement', '', 'bearing_displacement', {'bearing_displacement'}, {'warn_lines', 'group_warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('tilt', '倾角', 'tilt', '', 'tilt', 'tilt', 'tilt', '', 'tilt', {'tilt'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('gnss', 'GNSS', 'gnss', '', 'gnss', 'gnss', 'gnss', '', 'gnss', {'gnss'}, {'warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('acceleration', '加速度', 'acceleration', '', 'acceleration', 'acceleration', 'acceleration', '', 'acceleration', {'acceleration', 'acceleration_raw'}, {'warn_lines', 'group_warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('accel_spectrum', '加速度频谱', 'accel_spectrum', '', 'accel_spectrum', 'accel_spectrum', 'acceleration', 'accel_spectrum_params', 'acceleration_raw', {'accel_spectrum', 'acceleration', 'acceleration_raw'}, {'warn_lines'}, true), ...
                bms.config.ModuleConfigRegistry.make('cable_accel', '索力加速度', 'cable_accel', '', 'cable_accel', 'cable_accel', 'cable_accel', '', 'cable_accel', {'cable_accel', 'cable_accel_raw', 'cable_force'}, {'warn_lines', 'rms_warn_lines', 'group_warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('cable_accel_spectrum', '索力加速度频谱', 'cable_accel_spectrum', '', 'cable_accel_spectrum', 'cable_accel', 'cable_accel', 'cable_accel_spectrum_params', 'cable_accel_raw', {'cable_accel_spectrum', 'cable_accel', 'cable_accel_raw', 'cable_force'}, {'warn_lines'}, true), ...
                bms.config.ModuleConfigRegistry.make('strain', '应变', 'strain', '', 'strain', 'strain', 'strain', '', 'strain', {'strain'}, {'warn_lines', 'group_warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('dynamic_strain', '动应变高通', 'dynamic_strain', '', 'dynamic_strain', 'dynamic_strain', 'dynamic_strain', '', 'strain', {'dynamic_strain', 'dynamic_strain_highpass', 'strain'}, {'warn_lines', 'group_warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('dynamic_strain_lowpass', '动应变低通', 'dynamic_strain_lowpass', '', 'dynamic_strain_lowpass', 'dynamic_strain', 'dynamic_strain_lowpass', '', 'strain', {'dynamic_strain_lowpass', 'dynamic_strain', 'strain'}, {'warn_lines', 'group_warn_lines'}), ...
                bms.config.ModuleConfigRegistry.make('crack', '裂缝宽度', 'crack', '', 'crack', 'crack', 'crack', '', 'crack', {'crack', 'crack_temp'}, {'warn_lines'}) ...
                ];
        end

        function specs = plotModuleDefs()
            specs = bms.config.ModuleConfigRegistry.catalog();
        end

        function spec = fromKey(key)
            key = char(string(key));
            specs = bms.config.ModuleConfigRegistry.catalog();
            spec = bms.config.ModuleConfigRegistry.make(key, key, key, '', key, key, key, '', key, {key}, {'warn_lines'});
            for i = 1:numel(specs)
                if strcmp(specs(i).value, key) || strcmp(specs(i).style_key, key) || strcmp(specs(i).point_key, key)
                    spec = specs(i);
                    return;
                end
                if any(strcmp(specs(i).aliases, key))
                    spec = specs(i);
                    return;
                end
            end
        end

        function spec = normalize(specOrKey)
            if isstruct(specOrKey)
                spec = bms.config.ModuleConfigRegistry.fromKey(bms.config.ModuleConfigRegistry.structKey(specOrKey));
                names = fieldnames(specOrKey);
                for i = 1:numel(names)
                    spec.(names{i}) = specOrKey.(names{i});
                end
                spec = bms.config.ModuleConfigRegistry.fillMissing(spec);
            else
                spec = bms.config.ModuleConfigRegistry.fromKey(specOrKey);
            end
        end

        function keys = knownConfigKeys()
            specs = bms.config.ModuleConfigRegistry.catalog();
            keys = {};
            for i = 1:numel(specs)
                keys = [keys, {specs(i).value, specs(i).style_key, specs(i).point_key, ...
                    specs(i).per_point_key, specs(i).group_key, specs(i).params_key, ...
                    specs(i).subfolder_key}, specs(i).aliases(:)']; %#ok<AGROW>
            end
            keys = [keys, {'temp_humidity', 'wind_raw', 'eq_raw', 'acceleration_raw', ...
                'cable_accel_raw', 'cable_force', 'dynamic_strain_highpass', 'wim', ...
                'vibration', 'pending_gnss', 'pending_stress', 'eq_x', 'eq_y', 'eq_z'}];
            keys = unique(keys(~cellfun(@isempty, keys)), 'stable');
        end

        function aliases = aliasesForKey(key)
            spec = bms.config.ModuleConfigRegistry.fromKey(key);
            aliases = unique([{char(string(key)), spec.value, spec.style_key, spec.point_key, ...
                spec.per_point_key, spec.group_key, spec.subfolder_key}, spec.aliases(:)'], 'stable');
            aliases = aliases(~cellfun(@isempty, aliases));
        end

        function spec = make(value, label, styleKey, section, pointKey, perPointKey, groupKey, paramsKey, subfolderKey, aliases, warnFields, isSpectrum)
            if nargin < 12
                isSpectrum = false;
            end
            spec = struct();
            spec.value = char(string(value));
            spec.label = char(string(label));
            spec.style_key = char(string(styleKey));
            spec.section = char(string(section));
            spec.point_key = char(string(pointKey));
            spec.per_point_key = char(string(perPointKey));
            spec.group_key = char(string(groupKey));
            spec.params_key = char(string(paramsKey));
            spec.subfolder_key = char(string(subfolderKey));
            spec.aliases = cellstr(string(aliases(:)));
            spec.warn_fields = cellstr(string(warnFields(:)));
            spec.is_spectrum = logical(isSpectrum);
        end

        function spec = fillMissing(spec)
            defaults = bms.config.ModuleConfigRegistry.make('', '', '', '', '', '', '', '', '', {}, {});
            names = fieldnames(defaults);
            for i = 1:numel(names)
                name = names{i};
                if ~isfield(spec, name) || isempty(spec.(name))
                    spec.(name) = defaults.(name);
                end
            end
            if isempty(spec.style_key), spec.style_key = spec.value; end
            if isempty(spec.point_key), spec.point_key = spec.style_key; end
            if isempty(spec.per_point_key), spec.per_point_key = spec.point_key; end
            if isempty(spec.group_key), spec.group_key = spec.point_key; end
            if isempty(spec.subfolder_key), spec.subfolder_key = spec.point_key; end
        end

        function key = structKey(s)
            candidates = {'value', 'key', 'style_key', 'point_key'};
            key = '';
            for i = 1:numel(candidates)
                c = candidates{i};
                if isfield(s, c) && ~isempty(s.(c))
                    key = char(string(s.(c)));
                    return;
                end
            end
        end
    end
end
