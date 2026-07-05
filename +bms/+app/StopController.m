classdef StopController
    %STOPCONTROLLER Shared cooperative stop checks for analysis runs.

    methods (Static)
        function configure(stopFile)
            if nargin < 1
                stopFile = '';
            end
            bms.app.StopController.state('set', char(string(stopFile)));
        end

        function clear()
            bms.app.StopController.state('set', '');
        end

        function requestStop()
            global RUN_STOP_FLAG;
            RUN_STOP_FLAG = true;
        end

        function tf = isStopRequested()
            tf = false;
            try
                global RUN_STOP_FLAG;
                tf = ~isempty(RUN_STOP_FLAG) && logical(RUN_STOP_FLAG);
                if tf
                    return;
                end
            catch
                tf = false;
            end

            stopFile = bms.app.StopController.state('get');
            try
                tf = ~isempty(stopFile) && isfile(stopFile);
            catch
                tf = false;
            end
        end

        function throwIfRequested(message)
            if nargin < 1 || isempty(message)
                message = 'User requested stop';
            end
            if bms.app.StopController.isStopRequested()
                error('BMS:RunStopped', '%s', char(string(message)));
            end
        end
    end

    methods (Static, Access = private)
        function out = state(action, value)
            persistent stopFilePath
            if isempty(stopFilePath)
                stopFilePath = '';
            end
            switch lower(char(string(action)))
                case 'set'
                    if nargin < 2
                        value = '';
                    end
                    stopFilePath = char(string(value));
                    out = stopFilePath;
                otherwise
                    out = stopFilePath;
            end
        end
    end
end
