classdef JikangClient
    %JIKANGCLIENT Minimal Jikang HTTP API client for Hongtang lowfreq export.

    properties
        BaseUrl char = ''
        Username char = ''
        Password char = ''
        Token char = ''
        Timeout double = 60
        Endpoints struct = struct()
        TimeFormat char = 'yyyy-mm-dd HH:MM:SS'
        MaxPages double = 10000
    end

    methods
        function obj = JikangClient(credentials, varargin)
            if nargin < 1 || isempty(credentials)
                credentials = struct();
            end
            obj.BaseUrl = bms.data.JikangClient.fieldText(credentials, 'base_url', '');
            obj.Username = bms.data.JikangClient.fieldText(credentials, 'username', '');
            obj.Password = bms.data.JikangClient.fieldText(credentials, 'password', '');
            obj.Token = bms.data.JikangClient.fieldText(credentials, 'token', '');
            obj.Endpoints = struct( ...
                'devices', 'platformInfos/queryRtuListByProjectId.do', ...
                'parameters', 'platformInfos/queryParaidsDetailsByDeviceId.do', ...
                'history', 'dataChart/queryShareDataList.do');

            if mod(numel(varargin), 2) ~= 0
                error('JikangClient:InvalidOptions', 'Options must be name/value pairs.');
            end
            for i = 1:2:numel(varargin)
                key = lower(char(string(varargin{i})));
                value = varargin{i + 1};
                switch key
                    case 'timeout'
                        obj.Timeout = double(value);
                    case 'maxpages'
                        obj.MaxPages = double(value);
                    otherwise
                        error('JikangClient:UnknownOption', 'Unknown option: %s', key);
                end
            end
        end

        function rows = listDevices(obj, projectId)
            params = obj.authParams();
            params.projectId = char(string(projectId));
            payload = obj.getJson(obj.Endpoints.devices, params);
            flag = bms.data.JikangClient.payloadFlag(payload);
            if strcmp(flag, '4')
                rows = struct([]);
                return;
            end
            obj.assertFlag(payload, {'1'}, 'list devices');
            rows = bms.data.JikangClient.payloadRows(payload);
        end

        function rows = listSensors(obj, deviceId)
            params = obj.authParams();
            params.idCode = char(string(deviceId));
            payload = obj.getJson(obj.Endpoints.parameters, params);
            flag = bms.data.JikangClient.payloadFlag(payload);
            if strcmp(flag, '4')
                rows = struct([]);
                return;
            end
            obj.assertFlag(payload, {'1'}, 'list sensors');
            rows = bms.data.JikangClient.payloadRows(payload);
        end

        function rows = fetchSamples(obj, deviceId, startTime, endTime)
            startDt = bms.data.JikangClient.parseDateTime(startTime);
            endDt = bms.data.JikangClient.parseDateTime(endTime);
            if endDt <= startDt
                endDt = startDt + seconds(1);
            end

            rows = struct([]);
            currentStart = startDt;
            pageCount = 0;
            while currentStart <= endDt
                pageCount = pageCount + 1;
                if pageCount > obj.MaxPages
                    error('JikangClient:TooManyPages', ...
                        'Jikang history pagination exceeded %d pages for device %s.', obj.MaxPages, deviceId);
                end

                params = obj.authParams();
                params.idType = 0;
                params.idCode = char(string(deviceId));
                params.startTime = datestr(currentStart, obj.TimeFormat);
                params.endTime = datestr(endDt, obj.TimeFormat);
                params.dataType = 0;

                payload = obj.getJson(obj.Endpoints.history, params);
                flag = bms.data.JikangClient.payloadFlag(payload);
                if strcmp(flag, '4')
                    break;
                end
                if ~any(strcmp(flag, {'2', '3'}))
                    info = bms.data.JikangClient.fieldText(payload, 'info', '');
                    if isempty(info)
                        info = ['flag=' flag];
                    end
                    error('JikangClient:HistoryFailed', ...
                        'Jikang history query failed for %s: %s', deviceId, info);
                end

                page = bms.data.JikangClient.payloadRows(payload);
                rows = bms.data.JikangClient.concatRows(rows, page);
                if strcmp(flag, '3')
                    break;
                end

                nextStart = NaT;
                if isfield(payload, 'endTime') && ~isempty(payload.endTime)
                    nextStart = bms.data.JikangClient.parseDateTime(payload.endTime);
                end
                if isnat(nextStart)
                    error('JikangClient:MissingPageEnd', ...
                        'Jikang history pagination did not return endTime for %s.', deviceId);
                end
                if nextStart < currentStart
                    error('JikangClient:PageTimeRollback', ...
                        'Jikang history pagination rolled back for %s.', deviceId);
                end
                currentStart = nextStart + seconds(1);
            end
        end
    end

    methods (Access = private)
        function params = authParams(obj)
            if isempty(obj.BaseUrl)
                error('JikangClient:MissingBaseUrl', 'JIKANG_BASE_URL is missing.');
            end
            if isempty(obj.Username) || isempty(obj.Password)
                error('JikangClient:MissingCredentials', 'Jikang username/password are missing.');
            end
            params = struct('username', obj.Username, 'password', obj.Password);
            if ~isempty(obj.Token)
                params.token = obj.Token;
            end
        end

        function payload = getJson(obj, endpoint, params)
            url = [regexprep(obj.BaseUrl, '/+$', '') '/' regexprep(char(endpoint), '^/+', '')];
            opts = weboptions('Timeout', obj.Timeout, 'ContentType', 'json');
            names = fieldnames(params);
            args = cell(1, numel(names) * 2);
            for i = 1:numel(names)
                args{2*i-1} = names{i};
                args{2*i} = params.(names{i});
            end
            try
                payload = webread(url, args{:}, opts);
            catch ME
                error('JikangClient:RequestFailed', 'Jikang request failed: %s', ME.message);
            end
            if ~isstruct(payload)
                error('JikangClient:InvalidResponse', 'Jikang response is not a JSON object.');
            end
        end

        function assertFlag(~, payload, allowed, action)
            flag = bms.data.JikangClient.payloadFlag(payload);
            if ~any(strcmp(flag, allowed))
                info = bms.data.JikangClient.fieldText(payload, 'info', '');
                if isempty(info)
                    info = ['flag=' flag];
                end
                error('JikangClient:UnexpectedFlag', 'Jikang %s failed: %s', action, info);
            end
        end
    end

    methods (Static)
        function rows = payloadRows(payload)
            rows = struct([]);
            if ~isfield(payload, 'dataList') || isempty(payload.dataList)
                return;
            end
            rows = payload.dataList;
            if iscell(rows)
                if isempty(rows)
                    rows = struct([]);
                else
                    rows = [rows{:}];
                end
            end
            if ~isstruct(rows)
                error('JikangClient:InvalidDataList', 'Jikang dataList is not a struct array.');
            end
        end

        function rows = concatRows(a, b)
            if isempty(a)
                rows = b;
            elseif isempty(b)
                rows = a;
            else
                rows = [a(:); b(:)];
            end
        end

        function flag = payloadFlag(payload)
            flag = '';
            if isstruct(payload) && isfield(payload, 'flag') && ~isempty(payload.flag)
                flag = char(string(payload.flag));
            end
        end

        function value = fieldText(s, field, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = char(string(s.(field)));
            end
        end

        function dt = parseDateTime(value)
            if isa(value, 'datetime')
                dt = value;
                dt.TimeZone = '';
                return;
            end
            text = char(string(value));
            formats = {'yyyy-MM-dd HH:mm:ss', 'yyyy/MM/dd HH:mm:ss', ...
                'yyyy-MM-dd HH:mm', 'yyyy/MM/dd HH:mm', 'yyyy-MM-dd''T''HH:mm:ss'};
            dt = NaT;
            for i = 1:numel(formats)
                try
                    dt = datetime(text, 'InputFormat', formats{i});
                    return;
                catch
                end
            end
        end
    end
end
