# Extensions Chrome MPG – installeur

Installe et met à jour les extensions Chrome internes de l'équipe MPG dans `~/Extensions MPG`.
Lancé par le raccourci macOS **Extensions MPG** :

```
curl -fsSL https://raw.githubusercontent.com/frank-mpg/extension_installer/main/install.sh | bash
```

| Dossier installé | Dépôt |
|---|---|
| MPG Tools | [extension_auto_leagues](https://github.com/frank-mpg/extension_auto_leagues) |
| API URL | [extension_api_url](https://github.com/frank-mpg/extension_api_url) |
| Outils (custom user) | [extension_custom_user](https://github.com/frank-mpg/extension_custom_user) |
| MPP Prono Selector | [extension_mpp_points_calculator](https://github.com/frank-mpg/extension_mpp_points_calculator) |
| Bannière dynamique | [extension_ui_improvements](https://github.com/frank-mpg/extension_ui_improvements) |

Chaque lancement télécharge la dernière release de chaque extension. Les extensions déjà chargées dans Chrome se rechargent seules dans la minute.
