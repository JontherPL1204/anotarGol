# Credenciales por entorno

1. Copia `dev.example.json` a `dev.json` y pega los valores reales
   (Supabase > Project Settings > Data API / API Keys).
2. Corre la app pasando el archivo:

```bash
flutter run --dart-define-from-file=env/dev.json
```

`dev.json` y `prod.json` estan en `.gitignore`: no se versionan.

> El nombre viejo `SUPABASE_ANON_KEY` sigue funcionando: Supabase
> renombró el concepto a *publishable key*, pero el valor cumple la
> misma función y la app acepta los dos nombres.

## ¿Por qué no dejar la clave publicable en el código?

La clave publicable es **pública por diseño** (viaja dentro del APK y cualquiera
puede extraerla). Lo que protege los datos no es esa clave, sino las
políticas RLS de `supabase/migrations/…_04_rls.sql`.

Aun así se mantiene fuera del repositorio por dos razones prácticas:

- Dev y producción apuntan a bases distintas sin tocar código.
- Rotar la clave no obliga a un commit.

La que **nunca** puede salir del servidor es la `service_role` key: se
salta RLS por completo. No la uses en la app Flutter.
