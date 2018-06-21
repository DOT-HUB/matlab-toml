function val = parsevalue(str)
%% check for noncompletion
  if isempty(str)
    val = '';
    return
  end

%% default fixes
  % default behavior is direct passthrough
  val = str;

  % remove leading equals sign
  if val(1) == '='
    val = val(2:end);
  end

  % trim space on each side
  trimmed_val = strtrim(val);

%% check for numeric types

  % utils for integers
  is_int = @(t, s, c) all(ismember(t, [s, '_'])) && ...
           length(t) > 3 && isequal(t(1:2), ['0', c]);
  descore = @(t) strrep(t(3:end), '_', '');
  specs.bin = 'b01';
  specs.oct = 'o01234567';
  specs.dec = '_+-0123456789.eE';
  specs.hex = 'x0123456789abcdefABCDEF';
  % binary
  if is_int(trimmed_val, specs.bin, 'b')
    val = bin2dec(descore(trimmed_val));
  % octal
  elseif is_int(trimmed_val, specs.oct, 'o')
    val = base2dec(descore(trimmed_val), 8);
  % hexadecimal
  elseif is_int(trimmed_val, specs.hex, 'x')
    val = hex2dec(descore(trimmed_val));
  % decimal (including floats)
  elseif all(ismember(trimmed_val, specs.dec))
    val = str2double(strrep(val, '_', ''));
  end

  % special values of float
  if any(strcmp(trimmed_val, {'inf', '+inf', '-inf', 'nan', '+nan', '-nan'}))
    val = str2double(val);
  end

%% booleans
  if any(strcmp(trimmed_val, {'true', 'false'}))
    val = str2num(trimmed_val);
  end

%% strings
  % basic strings
  if trimmed_val(1) == '"'
    % is it multiline and complete?
    if isequal(trimmed_val(1:3), '"""') && ...
       numel(trimmed_val) > 3 && ...
       isequal(trimmed_val(end-2:end), '"""')
      % remove quotes
      val = trimmed_val(4:end-3);
      % remove leading newline
      if val(1) == sprintf('\n')
        val = val(2:end);
      end
      % trim whitespace for backslashes
      val = regexprep(val, '\\\n\s+', '');

    % is it complete but not multiline?
    elseif trimmed_val(2) ~= '"' && trimmed_val(end) == '"'
      % remove quotes
      val = trimmed_val(2:end-1);

    % newline in string, tell caller the value is incomplete
    else
      val = '';
      return
    end

    % common post-processing
    % escaped quotes
    val = strrep(val, '\"', '"');
    % escaped characters
    val = regexprep(val, '(\\[btnfr\\])', '${sprintf($1)}');
    % unicode points
    ucode_match = '\\(u[A-Fa-f0-9]{4}|U[A-Fa-f0-9]{8})';
    ucode_replace = '${char(hex2dec($1(2:end)))}';
    val = regexprep(val, ucode_match, ucode_replace);
  end

  % literal strings
  if trimmed_val(1) == ''''
    % is it multiline and complete?
    if isequal(trimmed_val(1:3), '''''''') && ...
       numel(trimmed_val) > 3 && ...
       isequal(trimmed_val(end-2:end), '''''''')
      % remove quotes
      val = trimmed_val(4:end-3);
      % remove leading newline
      if val(1) == sprintf('\n')
        val = val(2:end);
      end

    % is it complete but not multiline?
    elseif trimmed_val(2) ~= '''' && trimmed_val(end) == ''''
      % remove quotes
      val = trimmed_val(2:end-1);

    % newline in string, tell caller the value is incomplete
    else
      val = '';
      return
    end
  end

%% datetimes

  % make regexes
  is_match = @(s, p) ~isempty(regexp(s, p));
  whole_line_match = @(p) is_match(trimmed_val, ['^', p, '$']);
  date_regexp = '\d{4}-\d{2}-\d{2}';
  upto12 = '(01|02|03|04|05|06|07|08|09|10|11|12)';
  fract_sec = '\.\d{1,9}';
  time_regexp = [upto12, ':[0-6]\d:[0-6]\d(', fract_sec, ')?'];
  offset_regexp = ['(Z|[-+]', upto12, ':[0-6]\d(:[0-6]\d)?)'];

  % see what fits
  has_date = is_match(trimmed_val, date_regexp);
  has_time = is_match(trimmed_val, time_regexp);
  is_datetime = has_date && has_time;
  is_datetime_t = is_datetime && ...
      is_match(trimmed_val, [date_regexp, 'T', time_regexp]);
  is_datetime_space = is_datetime &&  ~is_datetime_t && ...
      is_match(trimmed_val, [date_regexp, ' ', time_regexp]);
  has_fr_sec = has_time && is_match(trimmed_val, fract_sec);
  has_offset = has_time && is_match(trimmed_val, offset_regexp);

  % make formats
  date_fmt = 'yyyy-MM-dd';
  time_fmt = 'HH:mm:ss';
  fract_sec_fmt = '.SSSSSSSSS';

  % do what we can with it
  if is_datetime
    dtargs = {};
    if is_datetime_t
      fmt_str = [date_fmt, '''T''', time_fmt];
    else
      fmt_str = [date_fmt, ' ', time_fmt];
    end
    if has_fr_sec
      fmt_str = [fmt_str, fract_sec_fmt];
    end
    if has_offset
      fmt_str = [fmt_str, 'Z'];
      dtargs = {'TimeZone', 'UTC'};
    end
    val = datetime(trimmed_val, 'InputFormat', fmt_str, dtargs{:});
  elseif has_date
    fmt_str = date_fmt;
    val = datetime(trimmed_val, 'InputFormat', fmt_str);
  elseif has_time
    fmt_str = time_fmt;
    if has_fr_sec
      fmt_str = [fmt_str, fract_sec_fmt];
    end
    val = datetime(trimmed_val, 'InputFormat', fmt_str);
  end

%% arrays

  if trimmed_val(1) == '['
    % is it all here yet?
    if trimmed_val(end) ~= ']'
      val = [];
      return
    % remove outer brackets
    else
      val = trimmed_val(2:end-1);
    end

    % split array while respecting nesting
    array_depth = 0;
    num_quotes = [0, 0];
    for ch = 1:length(val)
      switch val(ch)
        case '['
          array_depth = array_depth + 1;
        case ']'
          array_depth = array_depth - 1;
        case ''''
          num_quotes(1) = num_quotes(1) + 1;
        case '"'
          num_quotes(2) = num_quotes(2) + 1;
        case ','
          if array_depth == 0 && ~any(mod(num_quotes, 2))
            val(ch) = char(0);
          end
      end
    end
    val = strsplit(val, char(0));

    val = cellfun(@strtrim, val, 'uniformoutput', false);
    val = cellfun(@parsevalue, val, 'uniformoutput', false);
    if all(cellfun(@isnumeric, val))
      val = cell2mat(val);
    end
  end

end