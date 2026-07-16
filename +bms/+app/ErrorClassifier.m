classdef ErrorClassifier
    %ERRORCLASSIFIER Maps runtime failures to stable coarse error types.

    methods (Static)
        function errorType = classifyException(ME)
            if nargin < 1 || isempty(ME)
                errorType = '';
                return;
            end
            msg = bms.app.ErrorClassifier.safeExceptionText(ME, 'message');
            ident = bms.app.ErrorClassifier.safeExceptionText(ME, 'identifier');
            errorType = bms.app.ErrorClassifier.classifyText([ident ' ' msg]);
        end

        function errorType = classifyText(text)
            text = lower(char(string(text)));
            if isempty(strtrim(text))
                errorType = '';
            elseif bms.app.ErrorClassifier.isMemoryErrorText(text)
                errorType = 'memory_error';
            elseif bms.app.ErrorClassifier.hasAny(text, {'wim:sql','sqlcmd','sql server','odbc'})
                errorType = 'sql_error';
            elseif bms.app.ErrorClassifier.hasAny(text, {'wim:input','missingfmt','missingbcp', ...
                    'file missing','not found','no such file', ...
                    char([25991 20214 19981 23384 22312]), char([26410 25214 21040])})
                errorType = 'input_missing';
            elseif bms.app.ErrorClassifier.hasAny(text, {'unable to read','read failed', ...
                    char([26080 27861 35835 21462]), char([35835 21462 22833 36133])})
                errorType = 'read_failed';
            elseif bms.app.ErrorClassifier.hasAny(text, {'unrecognized field','config','field', ...
                    char([26080 27861 35782 21035 30340 23383 27573]), char([37197 32622])})
                errorType = 'config_invalid';
            elseif bms.app.ErrorClassifier.hasAny(text, {'writetable','xlsx','excel','stats'})
                errorType = 'stats_write_failed';
            elseif bms.app.ErrorClassifier.hasAny(text, {'save','.fig','.jpg','.emf','.png', ...
                    char([26080 27861 20445 23384])})
                errorType = 'plot_save_failed';
            else
                errorType = 'runtime_error';
            end
        end

        function tf = hasAny(text, patterns)
            tf = false;
            for i = 1:numel(patterns)
                if contains(text, lower(char(patterns{i})))
                    tf = true;
                    return;
                end
            end
        end

        function tf = isMemoryErrorText(text)
            % A bare "memory" match is unsafe: ordinary cache/file errors
            % would otherwise close figures and suppress later high-memory
            % modules.  Match MATLAB identifiers and unambiguous OOM phrases.
            patterns = { ...
                'matlab:nomem', ...
                'matlab:array:sizelimitexceeded', ...
                'out of memory', ...
                'outofmemory', ...
                'insufficient memory', ...
                'not enough memory', ...
                'cannot allocate memory', ...
                'failed to allocate memory', ...
                'java heap space', ...
                char([20869 23384 19981 36275]), ... % 内存不足
                char([26080 27861 20998 37197 20869 23384]), ... % 无法分配内存
                char([36229 36807 26368 22823 25968 32452 22823 23567])}; % 超过最大数组大小
            tf = bms.app.ErrorClassifier.hasAny(text, patterns);
        end

        function text = safeExceptionText(ME, fieldName)
            text = '';
            try
                text = char(ME.(fieldName));
            catch
            end
        end
    end
end
