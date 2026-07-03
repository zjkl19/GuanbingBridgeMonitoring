classdef PathProfileResolver
    %PATHPROFILERESOLVER Applies machine-specific path overrides.
    %
    % Bridge profiles keep business defaults. This resolver applies the
    % current machine's storage layout from config/path_profiles*.json.

    methods (Static)
        function profile = active(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            profile = bms.profile.PathProfileResolver.emptyProfile();
            entries = bms.profile.PathProfileResolver.loadProfiles(projectRoot);
            if isempty(entries)
                return;
            end

            requested = strtrim(char(string(getenv('GUANBING_PATH_PROFILE'))));
            if ~isempty(requested)
                idx = bms.profile.PathProfileResolver.findProfileById(entries, requested);
                if idx > 0
                    profile = entries(idx);
                end
                return;
            end

            host = lower(strtrim(char(string(getenv('COMPUTERNAME')))));
            if isempty(host)
                return;
            end
            for i = numel(entries):-1:1
                if bms.profile.PathProfileResolver.profileMatchesHost(entries(i), host)
                    profile = entries(i);
                    return;
                end
            end
        end

        function root = resolveDataRoot(bridgeId, defaultRoot, projectRoot)
            if nargin < 3 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            root = bms.profile.BridgeProfile.normalizePathText(defaultRoot);
            profile = bms.profile.PathProfileResolver.active(projectRoot);
            if ~isstruct(profile) || ~isfield(profile, 'profile_id') || isempty(profile.profile_id)
                return;
            end

            key = matlab.lang.makeValidName(lower(char(string(bridgeId))));
            if isfield(profile, 'data_roots') && isstruct(profile.data_roots) && isfield(profile.data_roots, key)
                candidate = bms.profile.PathProfileResolver.structText(profile.data_roots, key, '');
                if ~isempty(candidate)
                    root = bms.profile.PathProfileResolver.resolvePathTokens(candidate, projectRoot);
                    return;
                end
            end

            if isfield(profile, 'path_replacements')
                root = bms.profile.PathProfileResolver.applyReplacements(root, profile.path_replacements, projectRoot);
            end
        end

        function entries = loadProfiles(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            entries = struct([]);
            files = { ...
                fullfile(projectRoot, 'config', 'path_profiles.json'), ...
                fullfile(projectRoot, 'config', 'path_profiles.local.json')};
            for i = 1:numel(files)
                more = bms.profile.PathProfileResolver.loadFile(files{i});
                if isempty(more)
                    continue;
                end
                if isempty(entries)
                    entries = more;
                else
                    entries = [entries(:); more(:)]; %#ok<AGROW>
                end
            end
        end
    end

    methods (Static, Access = private)
        function profile = emptyProfile()
            profile = struct('profile_id', '', 'hostnames', {{}}, ...
                'data_roots', struct(), 'path_replacements', [], 'source_path', '');
        end

        function profiles = loadFile(path)
            profiles = struct([]);
            if exist(path, 'file') ~= 2
                return;
            end
            try
                data = jsondecode(fileread(path));
                if ~isfield(data, 'profiles')
                    return;
                end
                rows = data.profiles;
                for i = 1:numel(rows)
                    if iscell(rows)
                        row = rows{i};
                    else
                        row = rows(i);
                    end
                    row.source_path = path;
                    profiles = bms.profile.PathProfileResolver.appendProfile(profiles, row); %#ok<AGROW>
                end
            catch ME
                warning('BMS:PathProfile:LoadFailed', 'Failed to load path profile %s: %s', path, ME.message);
                profiles = struct([]);
            end
        end

        function profiles = appendProfile(profiles, row)
            base = bms.profile.PathProfileResolver.emptyProfile();
            names = intersect(fieldnames(row), fieldnames(base), 'stable');
            for i = 1:numel(names)
                base.(names{i}) = row.(names{i});
            end
            if isempty(profiles)
                profiles = base;
            else
                profiles(end+1, 1) = base;
            end
        end

        function idx = findProfileById(entries, profileId)
            idx = 0;
            wanted = lower(strtrim(char(string(profileId))));
            for i = numel(entries):-1:1
                current = '';
                if isfield(entries(i), 'profile_id') && ~isempty(entries(i).profile_id)
                    current = lower(strtrim(char(string(entries(i).profile_id))));
                end
                if strcmp(current, wanted)
                    idx = i;
                    return;
                end
            end
        end

        function tf = profileMatchesHost(profile, host)
            tf = false;
            if ~isfield(profile, 'hostnames') || isempty(profile.hostnames)
                return;
            end
            hosts = profile.hostnames;
            if ischar(hosts) || isstring(hosts)
                hosts = cellstr(string(hosts));
            elseif ~iscell(hosts)
                hosts = cellstr(string(hosts(:)));
            end
            for i = 1:numel(hosts)
                pat = lower(strtrim(char(string(hosts{i}))));
                if isempty(pat)
                    continue;
                end
                if strcmp(pat, host) || strcmp(pat, '*')
                    tf = true;
                    return;
                end
            end
        end

        function value = structText(s, fieldName, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                value = char(string(s.(fieldName)));
            end
        end

        function path = resolvePathTokens(path, projectRoot)
            path = bms.profile.BridgeProfile.normalizePathText(path);
            path = strrep(path, '<project_root>', projectRoot);
            path = strrep(path, '<COMPUTERNAME>', char(string(getenv('COMPUTERNAME'))));
        end

        function root = applyReplacements(root, replacements, projectRoot)
            if isempty(root) || isempty(replacements)
                return;
            end
            if iscell(replacements)
                rows = replacements;
            else
                rows = num2cell(replacements);
            end
            for i = 1:numel(rows)
                row = rows{i};
                if ~isstruct(row) || ~isfield(row, 'from') || ~isfield(row, 'to')
                    continue;
                end
                from = bms.profile.PathProfileResolver.resolvePathTokens(row.from, projectRoot);
                to = bms.profile.PathProfileResolver.resolvePathTokens(row.to, projectRoot);
                if isempty(from)
                    continue;
                end
                if bms.profile.PathProfileResolver.isPathPrefix(root, from)
                    root = [to root(numel(from)+1:end)];
                    root = bms.profile.BridgeProfile.normalizePathText(root);
                    return;
                end
            end
        end

        function tf = isPathPrefix(pathValue, prefixValue)
            pathValue = bms.profile.BridgeProfile.normalizePathText(pathValue);
            prefixValue = bms.profile.BridgeProfile.normalizePathText(prefixValue);
            pathLower = lower(pathValue);
            prefixLower = lower(prefixValue);
            tf = false;
            if ~startsWith(pathLower, prefixLower)
                return;
            end
            if numel(pathLower) == numel(prefixLower)
                tf = true;
                return;
            end
            nextChar = pathLower(numel(prefixLower) + 1);
            tf = any(nextChar == ['/' '\']);
        end
    end
end
