-- Dependencies
local function ensureHtmlDeps()
    quarto.doc.addHtmlDependency({
      name = "quiz",
      version = "1.0.0",
      scripts = {"quiz.js"},
      stylesheets = {"quiz.css"}
    })
  end
  
  -- Main filter
  function Div(el)
    if el.classes:includes("quiz") then
      ensureHtmlDeps()
      
      local title = el.attributes["title"] or "Untitled Quiz"
      local description = el.attributes["description"] or ""
      
      
      local quiz_div = pandoc.Div({
        pandoc.RawBlock('html', [[
          <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js"></script>
        ]]),
        pandoc.RawBlock('html', string.format([[
          <div class="quiz-container" 
               data-title="%s" 
               data-description="%s">
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
        ]], title, description, title, description))
      })
      
      return quiz_div
      
    elseif el.classes:includes("question") then
      ensureHtmlDeps()
      
      -- Find the question text (first Para block)
      local questionText = ""
      if el.content[1] and el.content[1].t == "Para" then
        questionText = pandoc.utils.stringify(el.content[1])
      end
      
      -- Parse options (look for BulletList)
      local options = {}
      for _, block in ipairs(el.content) do
        if block.t == "BulletList" then
          for _, item in ipairs(block.content) do
            local raw = pandoc.utils.stringify(item)
            local isCorrect = raw:match("%[x%]") or raw:match("☒")
            -- Remove both styles of checkboxes
            local text = raw:gsub("^%s*-%s*%[.%]%s*", "")  -- Remove ASCII style
            text = text:gsub("^%s*☐%s*", "")  -- Remove Unicode unchecked
            text = text:gsub("^%s*☒%s*", "")  -- Remove Unicode checked
            
            table.insert(options, {
              text = text,
              is_correct = isCorrect ~= nil
            })
          end
        end
      end
      
      -- Create JSON string of options
      local optionsJson = "["
      for i, opt in ipairs(options) do
        if i > 1 then optionsJson = optionsJson .. "," end
        optionsJson = optionsJson .. string.format(
          '{"text":"%s","is_correct":%s}',
          opt.text,
          opt.is_correct and "true" or "false"
        )
      end
      optionsJson = optionsJson .. "]"
      
      -- Create options HTML
      local optionsHtml = ""
      for i, opt in ipairs(options) do
        optionsHtml = optionsHtml .. string.format([[
          <div class="option" data-index="%d">
            <span class="option-text">%s</span>
            <span class="option-stats"></span>
          </div>
        ]], i-1, opt.text)
      end
      
      -- Create HTML
      local html = string.format([[
        <div class="question-container" 
             data-question="%s"
             data-options='%s'>
          <p class="question-text">%s</p>
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
      ]], questionText, optionsJson, questionText, optionsHtml)
      
      return pandoc.RawBlock('html', html)
    end
  end