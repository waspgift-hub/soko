content = open("src/services/mailer.js", encoding="utf-8").read()
start = content.index("function wrapEmailHtml")
end = content.index("async function sendMail")
new_func = "function wrapEmailHtml(html) { return `<div class=\"glass\">` + html + `</div>`; }\n\n"
content = content[:start] + new_func + content[end:]
open("src/services/mailer.js","w",encoding="utf-8").write(content)
print("done")
