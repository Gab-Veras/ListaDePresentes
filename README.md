# Lista de presentes para eventos

Web app mobile-first em React + Vite e Supabase. Eventos, categorias, presentes e convidados ficam isolados por `event_id`. A área pública não consulta convidados nem presentes reservados.

## Estrutura

- `src/App.jsx`: rotas, experiência pública e painel administrativo.
- `src/supabase.js`: cliente Supabase via variáveis de ambiente.
- `src/style.css`: estilos responsivos.
- `supabase/schema.sql`: tabelas, índices, RLS e reserva transacional.
- `public/_redirects`: fallback de rotas para Netlify.

## Supabase

1. Crie um projeto Supabase e abra **SQL Editor**.
2. Execute todo o arquivo `supabase/schema.sql`.
3. Para criar o evento e a lista inicial do chá de cozinha, execute `supabase/seed.sql` após o schema. A carga pode ser omitida; todos os eventos e itens também podem ser criados pelo painel.\n4. Em **Authentication → Users**, crie o usuário administrador com e-mail e senha. Desative o cadastro público em **Authentication → Settings → User Signups**.
5. Copie o UUID desse usuário e execute no SQL Editor: `insert into public.admins(user_id) values ('UUID-DO-ADMIN');` Cada administrador deve ser inserido explicitamente nessa tabela. Usuários autenticados que não estiverem em `admins` não podem acessar os dados administrativos.
6. Em **Project Settings → API**, copie Project URL e anon/public key.
7. Acesse `/` no endereço publicado para abrir o evento inicial.

A função `reserve_gifts` é a única via pública de escrita: valida evento e seleção, associa convidado por evento + nome + telefone e reserva todas as linhas atomicamente. Em concorrência, só uma tentativa consegue reservar um mesmo presente. As tabelas `guests` não têm política de leitura pública; os presentes reservados também não são legíveis pela role pública. A chave `service_role` nunca deve ser colocada no frontend.

## Variáveis

Crie `.env.local` na raiz:

```env
VITE_SUPABASE_URL=https://SEU-PROJETO.supabase.co
VITE_SUPABASE_ANON_KEY=SUA_CHAVE_ANON_PUBLIC
```

## Desenvolvimento

```sh
npm install
npm run dev
```

## Deploy Netlify

- Importe o repositório no Netlify.
- Build command: `npm run build`
- Publish directory: `dist`
- Adicione `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` nas variáveis de ambiente do site e faça deploy.
- `public/_redirects` direciona rotas do app para `index.html`.
