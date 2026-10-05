-- Carga inicial opcional: evento e itens do chá de cozinha do briefing.
with new_event as (
 insert into public.events(name,event_date,event_time,address,final_message,active)
 values (
  'Chá de cozinha', '2026-11-07', '16:00', 'Av. Luiz do Patrocínio Fernandes, 161 - Votorantim',
  'Seu presente foi reservado com sucesso. Lembre-se de levar o presente no dia do nosso chá de cozinha, 07/11/2026, às 16h.', true
 ) returning id
), new_categories as (
 insert into public.categories(event_id,name,sort_order)
 select e.id, c.name, c.ord from new_event e cross join (values ('Cozinha',1),('Banheiro',2),('Lavanderia e Limpeza',3),('Quarto',4)) c(name,ord)
 returning id,event_id,name
)
insert into public.gifts(event_id,category_id,name)
select c.event_id,c.id,g.name from new_categories c
join (values
 ('Cozinha','Assadeiras/marinex'),('Cozinha','Kit de pia (porta esponja, porta detergente, lixeira, rodo de pia)'),('Cozinha','Peneira'),('Cozinha','Descascador de legumes e colher de sorvete'),('Cozinha','Espremedor de limão'),('Cozinha','Escorredor de macarrão'),('Cozinha','Talheres de inox'),('Cozinha','Abridor de lata'),('Cozinha','Funil'),('Cozinha','Descanso de panela'),('Cozinha','Utensílios de cozinha de silicone'),('Cozinha','Porta-frios'),('Cozinha','Forma para pizza'),('Cozinha','Forma de bolo'),('Cozinha','Forma de bolo (fundo removível)'),('Cozinha','Potes plásticos multiuso'),('Cozinha','Tábua de corte e tesoura de cozinha'),('Cozinha','Tigelas'),('Cozinha','Pegador de massa'),('Cozinha','Jogo de xícaras'),('Cozinha','Jogo de taças'),('Cozinha','Jogo de sobremesa'),('Cozinha','Jogo de copos'),('Cozinha','Jogo americano'),('Cozinha','Jogo de pratos'),('Cozinha','Jogo de panelas'),('Cozinha','Frigideira'),('Cozinha','Mixer ou processador'),('Cozinha','Panela de pressão'),('Cozinha','Escorredor de louças'),('Cozinha','Pano de prato'),('Cozinha','Sanduicheira'),('Cozinha','Conjunto de potes herméticos'),('Cozinha','Amassador de batata'),('Cozinha','Colher medidora'),('Cozinha','Jarra de vidro'),('Cozinha','Porta-talheres'),('Cozinha','Descanso de copo'),('Cozinha','Rolo de massa'),
 ('Banheiro','Lixeira de banheiro'),('Banheiro','Conjunto de acessórios (porta escova, porta sabonete, etc.)'),('Banheiro','Jogo de toalhas de banho'),('Banheiro','Jogo de toalhas de rosto'),('Banheiro','Roupão'),
 ('Lavanderia e Limpeza','Vassoura e pá'),('Lavanderia e Limpeza','Rodo e balde'),('Lavanderia e Limpeza','Varal de chão'),('Lavanderia e Limpeza','Panos de chão e flanelas'),('Lavanderia e Limpeza','Prendedores de roupa'),('Lavanderia e Limpeza','Cesto de roupa suja'),('Lavanderia e Limpeza','Mop'),
 ('Quarto','Jogo de cama'),('Quarto','Cobertor de casal'),('Quarto','Edredom'),('Quarto','Travesseiros')
) as g(category,name) on g.category=c.name;
