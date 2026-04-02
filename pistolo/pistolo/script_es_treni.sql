DROP DATABASE IF EXISTS treniTalia;
CREATE DATABASE treniTalia;
use treniTalia;


CREATE table treni(
	numero int auto_increment primary key NOT NULL,
    giorno DATE NOT NULL,
    ora TIME NOT NULL,
    destinazione varchar(20) NOT NULL,
    categoria varchar(20) NOT NULL,
    UNIQUE(ora, destinazione, categoria)
);

CREATE table stazioni(
	ID_stazione int auto_increment primary key NOT NULL,
    nome_stazione varchar(20) NOT NULL
);

CREATE table fermate(
	
	id_stazione int,
    num_treno int,
    ora TIME NOT NULL,
    FOREIGN KEY (num_treno) references treni(numero)
		on delete cascade
        on update cascade,
	FOREIGN KEY (id_stazione) REFERENCES stazioni(ID_stazione)
		on delete cascade
        on update cascade
);


INSERT INTO stazioni(nome_stazione)
values ("santa_caterina"),
	("dunbo"),
	("busanello"),
	("napoli"),
	("foggia"),
	("roma");

INSERT INTO treni(giorno, ora, destinazione, categoria)
values ("2025-11-2", "11:30", "roma", "intercity"),
("2025-11-3", "13:50", "foggia", "diretto"),
("2025-11-10", "20:15", "napoli", "locale");

INSERT INTO fermate(id_stazione, num_treno, ora)
values(6, 1, "22:10"),
(5, 2, "14:20"),
(4, 1, "19:15");

update stazioni
set nome_stazione= "pozzuoli_centrale"
where id_stazione=1;

alter table stazioni
change column nome_stazione nome varchar(45);

alter table treni
change column citta citta_destinazione varchar(45) NOT NULL;

alter table treni 
modify column nome not null;