# Extensions Chrome MPG – installeur

Installe et met à jour les extensions Chrome internes de l'équipe MPG dans `~/Extensions MPG`.
Tuto d'installation : **https://frank-mpg.github.io/extension_installer/tuto.html**

Lancé par le raccourci macOS **Extensions MPG** :

```
curl -fsSL "https://raw.githubusercontent.com/frank-mpg/extension_installer/main/install.sh?t=$(date +%s)" | bash
```

| Dossier installé | Dépôt |
|---|---|
| Ligues de test | [extension_auto_leagues](https://github.com/frank-mpg/extension_auto_leagues) |
| Changer d'API | [extension_api_url](https://github.com/frank-mpg/extension_api_url) |
| Custom user | [extension_custom_user](https://github.com/frank-mpg/extension_custom_user) |
| Calcul des points pronos | [extension_mpp_points_calculator](https://github.com/frank-mpg/extension_mpp_points_calculator) |
| Thème et correctifs UI | [extension_ui_improvements](https://github.com/frank-mpg/extension_ui_improvements) |

Chaque lancement télécharge la dernière release de chaque extension. Les extensions déjà chargées dans Chrome se rechargent seules dans la minute.
