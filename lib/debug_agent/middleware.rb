require 'json'

module DebugAgent
  CHAT_HTML = <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Debug Agent</title>
    <style>
      *{margin:0;padding:0;box-sizing:border-box}
      body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0d1117;color:#c9d1d9;height:100vh;display:flex;flex-direction:column}
      #header{background:#161b22;padding:12px 24px;border-bottom:1px solid #30363d;display:flex;align-items:center;gap:12px}
      #header h1{font-size:18px;font-weight:600}
      #header .badge{background:#cc342d;color:#fff;padding:2px 8px;border-radius:12px;font-size:11px}
      #messages{flex:1;overflow-y:auto;padding:24px;max-width:960px;width:100%;margin:0 auto}
      .msg{margin-bottom:16px;max-width:80%}
      .msg.user{margin-left:auto}
      .msg .bubble{padding:12px 16px;border-radius:12px;font-size:14px;line-height:1.6}
      .msg.user .bubble{background:#1f6feb;color:#fff}
      .msg.assistant .bubble{background:#161b22;border:1px solid #30363d}
      .msg.assistant .bubble table{border-collapse:collapse;width:100%;margin:8px 0}
      .msg.assistant .bubble th,.msg.assistant .bubble td{border:1px solid #30363d;padding:6px 10px;text-align:left;font-size:13px}
      .msg.assistant .bubble th{background:#21262d}
      .msg.assistant .bubble pre{background:#0d1117;padding:8px 12px;border-radius:6px;overflow-x:auto;margin:8px 0;font-size:13px}
      .tool-event{font-size:12px;color:#8b949e;padding:4px 0;border-left:2px solid #30363d;padding-left:12px;margin:4px 0}
      .tool-event .tool-name{color:#58a6ff;font-weight:600}
      #input-area{background:#161b22;padding:16px 24px;border-top:1px solid #30363d}
      #input-form{max-width:960px;margin:0 auto;display:flex;gap:12px}
      #msg-input{flex:1;background:#0d1117;border:1px solid #30363d;color:#c9d1d9;padding:12px 16px;border-radius:8px;font-size:14px;outline:none}
      #msg-input:focus{border-color:#58a6ff}
      #send-btn{background:#238636;color:#fff;border:none;padding:12px 24px;border-radius:8px;font-size:14px;cursor:pointer;font-weight:600}
      #send-btn:hover{background:#2ea043}
      #send-btn:disabled{background:#21262d;color:#484f58;cursor:not-allowed}
    </style>
    </head>
    <body>
    <div id="header">
      <h1>Debug Agent</h1>
      <span class="badge">Ruby</span>
    </div>
    <div id="messages"></div>
    <div id="input-area">
      <form id="input-form">
        <input id="msg-input" placeholder="Ask about GC, threads, object counts, requests..." autocomplete="off" autofocus>
        <button id="send-btn" type="submit">Send</button>
      </form>
    </div>
    <script>
    var msgs=document.getElementById('messages');var form=document.getElementById('input-form');var input=document.getElementById('msg-input');var btn=document.getElementById('send-btn');
    function addMsg(r,t){var d=document.createElement('div');d.className='msg '+r;var b=document.createElement('div');b.className='bubble';if(r==='assistant')b.innerHTML=md(t);else b.textContent=t;d.appendChild(b);msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight;return b}
    function addTool(n,a){var d=document.createElement('div');d.className='tool-event';d.innerHTML='<span class="tool-name">tool:'+n+'</span>('+JSON.stringify(a)+')';msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight}
    function md(t){var d=document.createElement('div');d.textContent=t;return d.innerHTML.split('\n').join('<br>')}
    var cb=null,ct='';
    form.addEventListener('submit',async function(e){e.preventDefault();var m=input.value.trim();if(!m)return;addMsg('user',m);input.value='';btn.disabled=true;cb=null;ct='';
    try{var r=await fetch('/agent/api/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:m})});var reader=r.body.getReader();var dec=new TextDecoder();var buf='';
    while(true){var out=await reader.read();if(out.done)break;buf+=dec.decode(out.value,{stream:true});var ls=buf.split('\n');buf=ls.pop();
    for(var i=0;i<ls.length;i++){var l=ls[i];if(l.startsWith('event: '))var ev=l.slice(7).trim();else if(l.startsWith('data: ')){var da;try{da=JSON.parse(l.slice(6))}catch(ex){continue}if(ev==='token'){if(!cb)cb=addMsg('assistant','');ct+=da;cb.innerHTML=md(ct)}else if(ev==='tool_call')addTool(da.tool,da.args);else if(ev==='tool_result'){var d=document.createElement('div');d.className='tool-event';d.innerHTML='<span class="tool-name">result:'+da.tool+'</span>';var p=document.createElement('pre');p.style.fontSize='11px';p.textContent=JSON.stringify(da.result,null,2).slice(0,2000);d.appendChild(p);msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight}else if(ev==='done'){btn.disabled=false;input.focus()}}}}}catch(err){addMsg('assistant','Error: '+err.message)}btn.disabled=false;input.focus()});
    </script>
    </body>
    </html>
  HTML

  ##
  # Rack-compatible middleware. Works with Rack, Rails, Sinatra, etc.
  #
  # Usage (Rails/Rack):
  #   use DebugAgent::RackMiddleware
  #
  # Usage (Sinatra):
  #   require 'debug_agent'
  #   DebugAgent.install_sinatra(self)
  #
  class RackMiddleware
    def initialize(app, config = nil)
      @app = app
      @config = config || Config.from_env
      @engine = DebugEngine.new(@config)
      @base_path = @config.base_path
    end

    def call(env)
      path = env['PATH_INFO']

      # Chat UI
      if path == @base_path || path == @base_path + '/'
        return [200, { 'Content-Type' => 'text/html' }, [CHAT_HTML]]
      end

      # Chat API
      if path == "#{@base_path}/api/chat" && env['REQUEST_METHOD'] == 'POST'
        body = JSON.parse(env['rack.input'].read)
        message = body['message']

        response_body = []
        @engine.chat_stream(message).each do |event_type, data|
          response_body << "event: #{event_type}\n"
          response_body << "data: #{JSON.generate(data)}\n\n"
        end

        return [200, { 'Content-Type' => 'text/event-stream',
                        'Cache-Control' => 'no-cache' }, response_body]
      end

      # Tools API
      if path == "#{@base_path}/api/tools"
        return [200, { 'Content-Type' => 'application/json' },
                [JSON.generate({ tools: @engine.tools.all_schemas })]]
      end

      @app.call(env)
    end
  end

  ##
  # Install debug agent routes in a Sinatra app.
  #
  def self.install_sinatra(sinatra_app)
    engine = DebugEngine.new

    sinatra_app.get Config.from_env.base_path do
      content_type :html
      CHAT_HTML
    end

    sinatra_app.post "#{Config.from_env.base_path}/api/chat" do
      content_type 'text/event-stream'
      body = JSON.parse(request.body.read)
      stream do |out|
        engine.chat_stream(body['message']).each do |event_type, data|
          out << "event: #{event_type}\n"
          out << "data: #{JSON.generate(data)}\n\n"
        end
      end
    end

    sinatra_app.get "#{Config.from_env.base_path}/api/tools" do
      content_type :json
      JSON.generate({ tools: engine.tools.all_schemas })
    end
  end
end
