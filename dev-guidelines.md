#    Development Guidelines
This standard outlines conventions, patterns, and so on that must be observed throughout aenode development (with elixir).

## General Guidelines


- The software must be written considering future revisions.
    - i.e Code must easily accomodate changes



## Regression Avoidance conventionss

- ### Application Variables (for modules)
    -  While defining module parameters  single key value pairs must be avoided
    Wrong:
     ```    
     config :archethic, Archethic.Networking.IPLookup,
     Archethic.Networking.IPLookup.Static
     ```
    Correct:
     ```    
     config :archethic, Archethic.Networking.IPLookup,
     provider: Archethic.Networking.IPLookup.Static
     ```
