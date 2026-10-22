# Rotina+ — passo a passo
1. **Supabase**: crie um projeto > SQL Editor > cole `schema.sql` > Run.
2. Authentication > Providers: deixe "Email" ligado (e confirmação de e-mail, se quiser).
3. Project Settings > API: copie a URL e a chave **anon** para `config.js`.
4. **Netlify**: Add new site > Deploy manually > arraste esta pasta (ou suba no GitHub e conecte).
5. Supabase > Authentication > URL Configuration: coloque a URL do seu site da Netlify em "Site URL".
6. Edite `privacidade.html`: troque [NOME/CONTATO DO RESPONSÁVEL].
Nunca publique a chave `service_role`.
