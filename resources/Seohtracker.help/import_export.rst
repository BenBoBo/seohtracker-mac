=======================================
Importation and exportation as CSV file
=======================================

All the measurements you register inside Seohtracker are stored in its internal
database. But the data is yours, you should have access to it to back it up,
put it into another program, share it with friends, copy the data to the
`mobile client <mobile_client.html>`_, etc… Or maybe you already have
measurements and would like to import them into Seohtracker? You can import and
export the database using the appropriate options in the **File** menu.

Exportation of the database will generate a CSV (comma separated values) file
in plain text format. CSV files are easy to handle, modify, or import into
other programs. Seohtracker will generate a simple two column file where one
column contains the date of the measurement in **YYYY-MM-DD:HH-MM** and another
in **number/weight unit** format.

Such CSV files can be imported back. There are two options for CSV importation:

1. Replace the current database
2. Only add measurements

The first option will delete all your current measurements and insert the ones
found in the imported CSV file. The second option can be used to add specific
values to your database without replacing it. This can be useful if you want to
add values you recorded by hand or using another software. In both cases, the
CSV file will be scanned for entries in the format mentioned above, ignoring
all other values.

Importation of CSV files can be also started by dragging and dropping CSV files
onto the Seohtracker main window or the Dock icon. In both cases you should
drag a single file: if you drag more than one, any random will be picked and
the rest ignored!
