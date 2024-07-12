rm logs/init_errors.log
rm logs/orchestration.log
rm -r logs/sync.log
rm -r logs/2024*
rm -r logs/postgres/*
rm -r logs/mongo/*
rm -r logs/health/*
rm exported*
rm mongoFind*
sed -i "s/^pageNumber=.*/pageNumber=1/" "variables.ini"
