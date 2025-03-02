-- Dependencies
local function ensureHtmlDeps()
  quarto.doc.addHtmlDependency({
    name = "quiz",
    version = "1.0.0",
    scripts = {"quiz.js"},
    stylesheets = {"quiz.css"}
  })
end

-- Escape function for JSON attributes
local function escapeJSON(s)
  if s == nil then return "" end
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return s
end

-- Function to get environment variable or fallback to the provided value
local function getEnvOrValue(varName, defaultValue)
  local value = os.getenv(varName)
  if value and value ~= "" then
    return value
  else
    return defaultValue
  end
end

-- Main filter
function Div(el)
  if el.classes:includes("quiz") then
    ensureHtmlDeps()
    
    local title = el.attributes["title"] or "Untitled Quiz"
    local description = el.attributes["description"] or ""
    
    -- Check for API key in attributes or environment variable
    local api_key = el.attributes["api-key"] or ""
    local env_var_name = el.attributes["api-key-env"] or "QUIZ_API_KEY"
    
    -- If api-key attribute is not provided or empty, try to get from environment variable
    if api_key == "" then
      api_key = getEnvOrValue(env_var_name, "")
    end
    
    local quiz_div = pandoc.Div({
      pandoc.RawBlock('html', [[
        <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js"></script>
      ]]),
      pandoc.RawBlock('html', string.format([[
        <div class="quiz-container" 
             data-title="%s" 
             data-description="%s"
             data-api-key="%s"
             data-api-key-env="%s">
          <div class="quiz-header">
            <h3>%s</h3>
            <p class="quiz-description">%s</p>
            <button class="create-quiz">Create Quiz Session</button>
          </div>
          <div class="quiz-content" style="display: none;">
            <div class="qr-section">
              <div class="qr-container"></div>
              <div class="qr-info">
                <p class="qr-title">Join the quiz!</p>
                <p class="qr-subtitle">Scan the QR code or click the link below</p>
                <div class="qr-link-container"></div>
              </div>
            </div>
          </div>
        </div>
      ]], title, description, escapeJSON(api_key), escapeJSON(env_var_name), title, description))
    })
    
    return quiz_div
    
  elseif el.classes:includes("question") then
    ensureHtmlDeps()
    
    -- Step 1: Separate the content into question and options parts
    local questionBlocks = {}
    local bulletListIndex = nil
    
    for i, block in ipairs(el.content) do
      if block.t == "BulletList" then
        bulletListIndex = i
        break
      else
        table.insert(questionBlocks, block)
      end
    end
    
    -- Step 2: Process the question part
    local questionPandoc = pandoc.Pandoc(questionBlocks)
    local questionHtml = pandoc.write(questionPandoc, "html")
    
    -- Create a plain text version for the data attribute
    local questionPlainText = ""
    if #questionBlocks > 0 then
      questionPlainText = pandoc.utils.stringify(pandoc.Pandoc(questionBlocks))
    end
    
    -- Step 3: Process the options (BulletList)
    local options = {}
    local optionsHtml = ""
    
    if bulletListIndex then
      local bulletList = el.content[bulletListIndex]
      
      for i, item in ipairs(bulletList.content) do
        -- Get the first paragraph of the list item
        local firstPara = item[1]
        local isCorrect = false
        local optionContent = {}
        
        -- Check if there's a checkbox
        if firstPara and firstPara.content and #firstPara.content > 0 then
          local firstInline = firstPara.content[1]
          
          -- Check for checkbox in the text
          if firstInline.text then
            local text = firstInline.text
            isCorrect = text:match("%[x%]") or text:match("☒")
            
            -- Create a copy of the paragraph content for processing
            local newContent = pandoc.List()
            local skipFirst = false
            
            -- Check and remove the checkbox marker
            if text:match("^%s*-%s*%[.%]%s*") or text:match("^%s*☐%s*") or text:match("^%s*☒%s*") then
              -- Remove checkbox from text
              local newText = text:gsub("^%s*-%s*%[.%]%s*", ""):gsub("^%s*☐%s*", ""):gsub("^%s*☒%s*", "")
              
              if newText ~= "" then
                -- Replace the first inline with modified text
                local newFirstInline = firstInline:clone()
                newFirstInline.text = newText
                newContent:insert(newFirstInline)
              else
                -- Skip empty text node
                skipFirst = true
              end
              
              -- Add rest of content
              for j = 2, #firstPara.content do
                newContent:insert(firstPara.content[j])
              end
            else
              -- No checkbox found, keep content as is
              newContent = firstPara.content
            end
            
            -- Create new paragraph with processed content
            local newPara = pandoc.Para(newContent)
            
            -- Create a new list item with processed content
            local newItem = pandoc.List()
            newItem:insert(newPara)
            
            -- Copy any additional blocks from the original item
            for j = 2, #item do
              newItem:insert(item[j])
            end
            
            -- Get the original markdown by converting to markdown
            local optMarkdown = pandoc.write(pandoc.Pandoc(newItem), "markdown")
            -- Clean up markdown (remove some extra newlines, etc.)
            optMarkdown = optMarkdown:gsub("^\n+", ""):gsub("\n+$", "")
            
            -- Create a plain text version for display attributes
            local optPlainText = pandoc.utils.stringify(pandoc.Pandoc({pandoc.Plain(newContent)}))
            
            -- Create HTML version of the option content for display
            local optHtml = pandoc.write(pandoc.Pandoc(newItem), "html")
            -- Clean up HTML to remove unnecessary paragraph tags
            optHtml = optHtml:gsub("^%s*<p>", ""):gsub("</p>%s*$", "")
            
            -- Add to options list, including both plain text and markdown
            table.insert(options, {
              text = escapeJSON(optPlainText),
              markdown = escapeJSON(optMarkdown),
              html = optHtml,
              is_correct = isCorrect
            })
          end
        end
      end
    end
    
    -- Build options JSON, including markdown content
    local optionsJson = "["
    for i, opt in ipairs(options) do
      if i > 1 then optionsJson = optionsJson .. "," end
      optionsJson = optionsJson .. string.format(
        '{"text":"%s","markdown":"%s","is_correct":%s}',
        opt.text,
        opt.markdown,
        opt.is_correct and "true" or "false"
      )
    end
    optionsJson = optionsJson .. "]"
    
    -- Build options HTML
    local optionsHtmlStr = ""
    for i, opt in ipairs(options) do
      optionsHtmlStr = optionsHtmlStr .. string.format([[
        <div class="option" data-index="%d">
          <div class="option-text">%s</div>
          <span class="option-stats"></span>
        </div>
      ]], i-1, opt.html)
    end
    
    -- Create HTML
    local html = string.format([[
      <div class="question-container" 
           data-question="%s"
           data-question-markdown="%s"
           data-options='%s'>
        <div class="question-text">%s</div>
        <div class="options-display">%s</div>
        <div class="options-container"></div>
        <div class="question-status">
          <span class="answer-count" style="display: none;">0 answers</span>
        </div>
        <div class="question-buttons">
          <button class="submit-question">Present Question</button>
          <button class="close-question" style="display: none;">Close Question</button>
        </div>
      </div>
    ]], escapeJSON(questionPlainText), escapeJSON(questionMarkdown), optionsJson, questionHtml, optionsHtmlStr)
    
    return pandoc.RawBlock('html', html)
  end
end