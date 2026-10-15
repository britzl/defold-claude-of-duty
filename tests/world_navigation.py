"""Read the bounded Automation Bridge pages of a complete generated graph."""
def read_navigation(command):
    result = {key: [] for key in ('nodes', 'edges', 'surfaces', 'flanks', 'stairs')}
    offset = 0
    while True:
        page = command('world.navigation', {'offset': offset, 'limit': 32})
        for key in result:
            result[key].extend(page[key])
        offset += page['limit']
        if offset >= max(page['counts'].values()):
            assert all(len(result[key]) == page['counts'][key] for key in result)
            return result
