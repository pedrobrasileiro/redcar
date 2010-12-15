
class ProjectSearch
  class WordSearchController
    include Redcar::HtmlController

    def title
      "Project Search"
    end
    
    def search_copy
      "Search for complete words only"
    end
    
    def show_literal_match_option?
      false
    end

    def num_context_lines
      settings['context_lines']
    end
    
    def plugin_root
      File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
    end
    
    def settings
      ProjectSearch.storage
    end
    
    def match_case?
      ProjectSearch.storage['match_case']
    end
    
    def context?
      ProjectSearch.storage['with_context']
    end
    
    def context_size
      context? ? num_context_lines : 0
    end
    
    def default_query
      doc.selected_text if doc && doc.selection?
    end
    
    def index
      render('index')
    end

    def edit_preferences
      Redcar.app.make_sure_at_least_one_window_open # open a new window if needed
      Redcar::FindInProject.storage # populate the file if it isn't already
      tab  = Redcar.app.focussed_window.new_tab(Redcar::EditTab)
      mirror = Project::FileMirror.new(File.join(Redcar.user_dir, "storage", "find_in_project.yaml"))
      tab.edit_view.document.mirror = mirror
      tab.edit_view.reset_undo
      tab.focus
    end

    def open_file(file, line, query, literal_match, match_case)
      Redcar::Project::Manager.open_file(File.expand_path(file, Redcar::Project::Manager.focussed_project.path))
      doc.cursor_offset = doc.offset_at_line(line.to_i - 1)
      regexp_text = literal_match ? Regexp.escape(query) : query
      regex = match_case ? /(#{regexp_text})/ : /(#{regexp_text})/i
      index = doc.get_line(line.to_i - 1).index(regex)
      if index
        length = doc.get_line(line.to_i - 1).match(regex)[1].length
        doc.set_selection_range(doc.cursor_line_start_offset + index, doc.cursor_line_start_offset + index + length)
      end
      doc.scroll_to_line(line.to_i)
      nil
    end

    def close
      Thread.kill(@thread) if @thread
      @thread = nil
      super
    end
    
    def render(view)
      rhtml = ERB.new(File.read(File.join(File.dirname(__FILE__), "views", "#{view.to_s}.html.erb")))
      rhtml.result(binding)
    end

    def doc
      Redcar.app.focussed_window.focussed_notebook_tab.edit_view.document rescue false
    end

    def add_or_move_to_top(item, array)
      return array if item.strip.empty?
      array.delete_at(array.index(item)) if array.include?(item)
      array.unshift(item)
    end

    def search(query, literal_match, match_case, with_context)
      ProjectSearch.storage['recent_queries'] = add_or_move_to_top(query, ProjectSearch.storage['recent_queries'])
      ProjectSearch.storage['match_case']     = (match_case == 'true')
      ProjectSearch.storage['with_context']   = (with_context == 'true')
      
      project = Redcar::Project::Manager.focussed_project
      
      @word_search = WordSearch.new(project, query, match_case?, context_size)
      
      # kill any existing running search to prevent memory bloat
      Thread.kill(@thread) if @thread
      @thread = nil
      @thread = Thread.new do
        begin
          initialize_search_output
          if @word_search.results.any?
            add_initial_table
            file_num = 0
            last_matching_line_num = nil
            previous_file = nil
            @word_search.results.each do |hit|
              file_num += 1 if hit.file != previous_file
              matched_lines      = false
              @line_index = 0 # reset line row styling
              need_context_after = 0
              
              add_initial_table
              
              if hit.file != previous_file
                increment_file_results_count
                add_break_row # if matched_lines
                render_file_heading(hit.file, file_num)
                @line_index = 0 # reset line row styling
              end
              
              if @word_search.context? && !(hit.file != previous_file) && (hit.line_num - last_matching_line_num) > (@word_search.context_size * 2)
                render_divider(file_num)
              end
              
              hit.pre_context.each_with_index do |context_line, i|
                render_line(file_num, hit.line_num - @word_search.context_size + i, hit.file, context_line)
              end
              
              render_line(file_num, hit.line_num, hit.file, hit.line)
              
              hit.post_context.each_with_index do |context_line, i|
                render_line(file_num, hit.line_num + i + 1, hit.file, context_line)
              end
              
              increment_line_results_count
              
              matched_lines          = true
              last_matching_line_num = hit.line_num
              
              previous_file = hit.file
            end
            remove_initial_blank_tr
          else
            render_no_results
          end
          hide_spinner
          Thread.kill(@thread) if @thread
          @thread = nil
        rescue => e
          puts e.message
          puts e.backtrace
        end
      end
      nil
    end
    
    def initialize_search_output
      execute("$('#cached_query').val(\"#{escape_javascript(@word_search.query_string)}\");")
      execute("$('#results').html(\"<div id='no_results'>Searching...</div>\");")
      execute("$('#spinner').show();")
      execute("$('#results_summary').hide();")
      execute("$('#file_results_count').html(0);")
      execute("$('#line_results_count').html(0);")
    end
    
    def add_initial_table
      # Add an initial <tr></tr>  so that tr:last can be used
      execute("if ($('#results table').size() == 0) { $('#results').html(\"<table><tr></tr></table>\"); }")
      execute("if ($('#results_summary').first().is(':hidden')) { $('#results_summary').show(); }")
    end
    
    def increment_file_results_count
      execute("$('#file_results_count').html(parseInt($('#file_results_count').html()) + 1);")
    end
    
    def add_break_row
      execute("$('#results table tr:last').after(\"<tr><td class='break' colspan='2'></td></tr>\");")
    end
    
    def render_file_heading(name, num)
      @file_name, @file_num = name, num
      execute("$('#results table tr:last').after(\"#{escape_javascript(render('_file_heading'))}\");")
    end
    
    def render_divider(line_file_num)
      @line_file_num = line_file_num
      execute("$('#results table tr:last').after(\"#{escape_javascript(render('_divider'))}\");")
    end
    
    def increment_line_results_count
      execute("$('#line_results_count').html(parseInt($('#line_results_count').html()) + 1);")
    end
    
    def remove_initial_blank_tr
      execute("$('#results table tr:first').remove();")
    end

    def render_no_results
      result = "<div id='no_results'>No results were found using the search terms you provided.</div>"
      execute("$('#results').html(\"#{escape_javascript(result)}\");")
    end
    
    def hide_spinner
      execute("$('#spinner').hide();")
    end

    def matching_line?(line_text)
      line_text =~ @regexp
    end

    def escape_javascript(text)
      escape_map = { '\\' => '\\\\', '</' => '<\/', "\r\n" => '\n', "\n" => '\n', "\r" => '\n', '"' => '\\"', "'" => "\\'" }
      text.to_s.gsub(/(\\|<\/|\r\n|[\n\r"'])/) { escape_map[$1] }
    end

    def render_line(file_num, line_num, file_name, line_text)
      @line_index += 1
      @file_num, @line_num, @file_name, @line_text = file_num, line_num, file_name, line_text
      execute("if ($('#results tr.file_#{file_num}.line_#{line_num}').size() == 0) {
        $('#results table tr:last').after(\"#{escape_javascript(render('_file_line'))}\");
      }")
    end
  end
end